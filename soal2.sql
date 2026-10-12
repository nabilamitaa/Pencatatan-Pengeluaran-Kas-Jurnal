-- SOAL 2 (jalankan setelah soal1.sql)

-- Tabel dari soal
CREATE TABLE inventory_items (item_id VARCHAR(10) PRIMARY KEY, item_name VARCHAR(100), stock_qty INT NOT NULL DEFAULT 0, unit_cost NUMERIC(15,2) NOT NULL);
CREATE TABLE inventory_transactions (trx_id SERIAL PRIMARY KEY, item_id VARCHAR(10) REFERENCES inventory_items(item_id), trx_type VARCHAR(10) CHECK (trx_type IN ('PURCHASE','SALE','ADJUSTMENT')), qty INT NOT NULL, trx_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP);

-- Akun yang dipakai jurnal otomatis Soal 2
INSERT INTO chart_of_accounts (account_code, account_name, normal_balance, report_class) VALUES
('1-300', 'Persediaan Barang Dagang', 'D', 'NERACA'),
('2-100', 'Utang Usaha',              'K', 'NERACA'),
('5-100', 'Beban Pokok Pendapatan',   'D', 'LABA_RUGI')
ON CONFLICT (account_code) DO NOTHING;

-- SOAL 2.1 - Trigger persediaan + jurnal otomatis
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

CREATE TRIGGER trg_inventory
BEFORE INSERT ON inventory_transactions
FOR EACH ROW
EXECUTE FUNCTION trg_update_stock_and_journal();

-- SOAL 2.2 - contoh data untuk demonstrasi
INSERT INTO inventory_items VALUES ('C01', 'Palet', 2, 50000);

-- SOAL 2.2 - Solusi 1: SELECT ... FOR UPDATE
BEGIN;
SELECT stock_qty FROM inventory_items
WHERE item_id = 'C01'
FOR UPDATE;            -- kasir B menunggu di sini

UPDATE inventory_items SET stock_qty = stock_qty - 1
WHERE item_id = 'C01' AND stock_qty >= 1;

COMMIT;                -- kunci dilepas

-- SOAL 2.2 - Solusi 2: SERIALIZABLE
BEGIN ISOLATION LEVEL SERIALIZABLE;
INSERT INTO inventory_transactions (item_id, trx_type, qty)
VALUES ('C01', 'SALE', 1);
COMMIT;
