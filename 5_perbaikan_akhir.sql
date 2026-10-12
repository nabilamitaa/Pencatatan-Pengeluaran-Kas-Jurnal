-- ===== 5_perbaikan_akhir.sql : jalankan SEKALI (F5) di database yang sama =====
-- Menutup celah: hapus baris jurnal, akali status REVERSED, qty negatif,
-- dan menambah fungsi simpan_voucher untuk formulir web.

-- Soal 1.2: cek keseimbangan juga saat baris dihapus
CREATE OR REPLACE FUNCTION cek_seimbang() RETURNS TRIGGER AS $$
DECLARE v_id INT := COALESCE(NEW.header_id, OLD.header_id);
BEGIN
    IF (SELECT SUM(debit) <> SUM(credit) FROM journal_lines
        WHERE header_id = v_id) THEN
        RAISE EXCEPTION 'Jurnal % tidak seimbang', v_id;
    END IF;
    RETURN NULL;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cek_seimbang ON journal_lines;
CREATE CONSTRAINT TRIGGER trg_cek_seimbang
AFTER INSERT OR UPDATE OR DELETE ON journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION cek_seimbang();

-- Soal 2.1: validasi qty dan barang
CREATE OR REPLACE FUNCTION trg_update_stock_and_journal()
RETURNS TRIGGER AS $$
DECLARE
    v_stok   INT;
    v_harga  NUMERIC(15,2);
    v_nilai  NUMERIC(18,2);
    v_jurnal INT;
    v_debit  VARCHAR(10);
    v_kredit VARCHAR(10);
BEGIN
    -- validasi: PURCHASE dan SALE wajib positif, ADJUSTMENT tidak boleh 0
    IF (NEW.trx_type IN ('PURCHASE', 'SALE') AND NEW.qty <= 0)
       OR (NEW.trx_type = 'ADJUSTMENT' AND NEW.qty = 0) THEN
        RAISE EXCEPTION 'Qty % tidak valid untuk %', NEW.qty, NEW.trx_type;
    END IF;

    -- kunci baris barang agar tidak diubah transaksi lain
    SELECT stock_qty, unit_cost INTO v_stok, v_harga
    FROM inventory_items
    WHERE item_id = NEW.item_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Barang % tidak terdaftar', NEW.item_id;
    END IF;

    -- (a) hitung stok baru sesuai jenis transaksi
    IF NEW.trx_type = 'PURCHASE' THEN
        v_stok := v_stok + NEW.qty;
    ELSIF NEW.trx_type = 'SALE' THEN
        v_stok := v_stok - NEW.qty;
    ELSE  -- ADJUSTMENT: qty boleh + atau -
        v_stok := v_stok + NEW.qty;
    END IF;

    -- (b) cegah stok negatif
    IF v_stok < 0 THEN
        RAISE EXCEPTION 'Stok % tidak cukup', NEW.item_id;
    END IF;

    UPDATE inventory_items
    SET stock_qty = v_stok
    WHERE item_id = NEW.item_id;

    -- (c) jurnal otomatis agar akun Persediaan & HPP ikut termutakhir
    IF NEW.trx_type IN ('PURCHASE', 'SALE') THEN
        v_nilai := NEW.qty * v_harga;
        IF NEW.trx_type = 'SALE' THEN
            v_debit := '5-100';  v_kredit := '1-300';  -- Dr HPP, Cr Persediaan
        ELSE
            v_debit := '1-300';  v_kredit := '2-100';  -- Dr Persediaan, Cr Utang Usaha
        END IF;

        INSERT INTO journal_headers (trx_date, reference_no, description)
        VALUES (NEW.trx_date::date, 'INV-' || NEW.trx_id, NEW.trx_type || ' ' || NEW.item_id)
        RETURNING header_id INTO v_jurnal;

        INSERT INTO journal_lines (header_id, account_id, debit, credit) VALUES
          (v_jurnal, (SELECT account_id FROM chart_of_accounts WHERE account_code = v_debit),  v_nilai, 0),
          (v_jurnal, (SELECT account_id FROM chart_of_accounts WHERE account_code = v_kredit), 0, v_nilai);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Soal 3.2: kunci POSTED diperketat
CREATE OR REPLACE FUNCTION kunci_posted() RETURNS TRIGGER AS $$
BEGIN
    -- satu-satunya perubahan yang diizinkan: POSTED -> REVERSED,
    -- dan kolom lain harus tetap sama persis
    IF OLD.posting_status <> 'DRAFT'
       AND NOT (TG_OP = 'UPDATE' AND OLD.posting_status = 'POSTED'
                AND NEW.posting_status = 'REVERSED'
                AND to_jsonb(NEW) - 'posting_status' = to_jsonb(OLD) - 'posting_status') THEN
        RAISE EXCEPTION 'Jurnal POSTED tidak boleh diubah/dihapus, gunakan storno';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

-- (6) RPC untuk formulir web (Soal 3.1a): simpan voucher sekaligus semua barisnya
CREATE OR REPLACE FUNCTION simpan_voucher(p_tanggal DATE, p_nomor TEXT,
                                          p_keterangan TEXT, p_baris JSONB)
RETURNS INT AS $$
DECLARE
    v_id   INT;
    v_akun INT;
    b      JSONB;
BEGIN
    INSERT INTO journal_headers (trx_date, reference_no, description)
    VALUES (p_tanggal, p_nomor, p_keterangan)
    RETURNING header_id INTO v_id;

    FOR b IN SELECT * FROM jsonb_array_elements(p_baris) LOOP
        SELECT account_id INTO v_akun FROM chart_of_accounts
        WHERE account_code = b->>'akun';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Akun % tidak ditemukan', b->>'akun';
        END IF;
        INSERT INTO journal_lines (header_id, account_id, debit, credit)
        VALUES (v_id, v_akun, (b->>'debit')::NUMERIC, (b->>'kredit')::NUMERIC);
    END LOOP;
    RETURN v_id;   -- keseimbangan tetap dicek trigger trg_cek_seimbang
END; $$ LANGUAGE plpgsql;
