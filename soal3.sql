-- SOAL 3.2 - Audit trail, immutability, dan RPC formulir (jalankan setelah soal2.sql)

-- (1) Kolom audit
ALTER TABLE journal_headers
    ADD COLUMN created_by    TEXT        DEFAULT current_user,
    ADD COLUMN created_at    TIMESTAMPTZ DEFAULT now(),
    ADD COLUMN hash_checksum TEXT;

-- (2) Kunci jurnal POSTED dari UPDATE dan DELETE
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

CREATE TRIGGER trg_kunci_posted
BEFORE UPDATE OR DELETE ON journal_headers
FOR EACH ROW EXECUTE FUNCTION kunci_posted();

-- Baris jurnal milik jurnal POSTED juga dikunci
CREATE OR REPLACE FUNCTION kunci_baris() RETURNS TRIGGER AS $$
BEGIN
    IF (SELECT posting_status FROM journal_headers
        WHERE header_id = OLD.header_id) <> 'DRAFT' THEN
        RAISE EXCEPTION 'Baris jurnal POSTED tidak boleh diubah/dihapus';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_kunci_baris
BEFORE UPDATE OR DELETE ON journal_lines
FOR EACH ROW EXECUTE FUNCTION kunci_baris();

-- (3) Rumus hash checksum (SHA-256 dari isi jurnal)
CREATE OR REPLACE FUNCTION hitung_hash(p_id INT) RETURNS TEXT AS $$
    SELECT encode(sha256(convert_to(concat_ws('|',
           h.header_id, h.trx_date, h.reference_no, h.created_by, h.created_at,
           (SELECT string_agg(concat_ws(':', account_id, debit, credit), ','
                              ORDER BY line_id)
            FROM journal_lines WHERE header_id = p_id)), 'UTF8')), 'hex')
    FROM journal_headers h
    WHERE h.header_id = p_id;
$$ LANGUAGE sql;

-- (4) Posting: DRAFT -> POSTED dan simpan hash
CREATE OR REPLACE FUNCTION post_journal(p_id INT) RETURNS VOID AS $$
BEGIN
    UPDATE journal_headers
    SET posting_status = 'POSTED',
        hash_checksum  = hitung_hash(p_id)
    WHERE header_id = p_id AND posting_status = 'DRAFT';
END; $$ LANGUAGE plpgsql;

-- (5) Jurnal pembalik (storno)
CREATE OR REPLACE FUNCTION reverse_journal(p_id INT) RETURNS INT AS $$
DECLARE v_baru INT;
BEGIN
    INSERT INTO journal_headers (trx_date, reference_no, description)
    SELECT CURRENT_DATE, 'REV-' || reference_no, 'Storno ' || reference_no
    FROM journal_headers WHERE header_id = p_id AND posting_status = 'POSTED'
    RETURNING header_id INTO v_baru;

    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    SELECT v_baru, account_id, credit, debit      -- debit & kredit ditukar
    FROM journal_lines WHERE header_id = p_id;

    PERFORM post_journal(v_baru);
    UPDATE journal_headers SET posting_status = 'REVERSED'
    WHERE header_id = p_id;
    RETURN v_baru;
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

-- (7) Verifikasi integritas: hitung ulang hash lalu bandingkan
SELECT reference_no, posting_status,
       hash_checksum = hitung_hash(header_id) AS data_utuh
FROM journal_headers
WHERE hash_checksum IS NOT NULL;
