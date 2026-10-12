-- ===== uji_jawaban.sql : untuk database BARU (setelah soal1, soal2, soal3) =====
-- Jalankan SATU BLOK SAJA setiap kali (sorot blok, lalu F5).

-- BLOK A: data contoh akun (BERHASIL)
INSERT INTO chart_of_accounts (account_code, account_name, normal_balance, report_class)
VALUES ('1-100','Kas','D','NERACA'), ('6-100','Beban Listrik','D','LABA_RUGI');

-- BLOK B: debit dan kredit nol (harus ERROR)
INSERT INTO journal_headers (trx_date, reference_no) VALUES ('2026-10-19','UJI-0');
INSERT INTO journal_lines (header_id, account_id, debit, credit)
VALUES (currval('journal_headers_header_id_seq'), (SELECT account_id FROM chart_of_accounts WHERE account_code='1-100'), 0, 0);

-- BLOK C: jurnal tidak seimbang (harus ERROR "tidak seimbang")
BEGIN;
INSERT INTO journal_headers (trx_date, reference_no) VALUES ('2026-10-19','UJI-1');
INSERT INTO journal_lines (header_id, account_id, debit, credit)
VALUES (currval('journal_headers_header_id_seq'), (SELECT account_id FROM chart_of_accounts WHERE account_code='6-100'), 500000, 0),
       (currval('journal_headers_header_id_seq'), (SELECT account_id FROM chart_of_accounts WHERE account_code='1-100'), 0, 400000);
COMMIT;

-- BLOK D: jurnal seimbang BKK-001 (BERHASIL)
BEGIN;
INSERT INTO journal_headers (trx_date, reference_no) VALUES ('2026-10-19','BKK-001');
INSERT INTO journal_lines (header_id, account_id, debit, credit)
VALUES (currval('journal_headers_header_id_seq'), (SELECT account_id FROM chart_of_accounts WHERE account_code='6-100'), 500000, 0),
       (currval('journal_headers_header_id_seq'), (SELECT account_id FROM chart_of_accounts WHERE account_code='1-100'), 0, 500000);
COMMIT;

-- BLOK 1: barang baru dengan stok 1 (BERHASIL)
INSERT INTO inventory_items VALUES ('B02', 'Map Plastik', 1, 15000)
ON CONFLICT (item_id) DO NOTHING;

-- BLOK 2: jual 2 padahal stok 1 (harus ERROR "Stok B02 tidak cukup")
INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('B02', 'SALE', 2);

-- BLOK 3: beli 4 (BERHASIL)
INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('B02', 'PURCHASE', 4);

-- BLOK 4: jual 3 (BERHASIL)
INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('B02', 'SALE', 3);

-- BLOK 5: lihat stok dan jurnal otomatis (stok B02 = 2; ada jurnal Persediaan & HPP)
SELECT * FROM inventory_items WHERE item_id = 'B02';
SELECT h.reference_no, h.description, a.account_name, l.debit, l.credit
FROM journal_lines l
JOIN journal_headers h USING (header_id)
JOIN chart_of_accounts a USING (account_id)
WHERE h.description LIKE '%B02%'
ORDER BY l.line_id;

-- BLOK 6: posting jurnal BKK-001 (BERHASIL)
SELECT post_journal((SELECT header_id FROM journal_headers WHERE reference_no = 'BKK-001'));

-- BLOK 7: ubah jurnal POSTED (harus ERROR "Jurnal POSTED tidak boleh diubah")
UPDATE journal_headers SET description = 'ubah' WHERE reference_no = 'BKK-001';

-- BLOK 8: ubah baris jurnal POSTED (harus ERROR "Baris jurnal POSTED tidak boleh diubah")
UPDATE journal_lines SET debit = 1
WHERE header_id = (SELECT header_id FROM journal_headers WHERE reference_no = 'BKK-001');

-- BLOK 9: koreksi dengan storno (BERHASIL)
SELECT reverse_journal((SELECT header_id FROM journal_headers WHERE reference_no = 'BKK-001'));

-- BLOK 10: verifikasi integritas (BKK-001 = REVERSED, REV-BKK-001 = POSTED, data_utuh = true)
SELECT reference_no, posting_status, hash_checksum,
       hash_checksum = hitung_hash(header_id) AS data_utuh
FROM journal_headers
WHERE hash_checksum IS NOT NULL;

-- BLOK P1: coba akali jurnal POSTED (harus ERROR "Jurnal POSTED tidak boleh diubah")
UPDATE journal_headers
SET posting_status = 'REVERSED', description = 'diubah diam-diam'
WHERE reference_no = 'REV-BKK-001';

-- BLOK P2: buat jurnal DRAFT yang seimbang (BERHASIL)
BEGIN;
INSERT INTO journal_headers (trx_date, reference_no, description)
VALUES ('2026-10-19', 'D-001', 'Uji hapus baris');
INSERT INTO journal_lines (header_id, account_id, debit, credit)
VALUES (currval('journal_headers_header_id_seq'), (SELECT account_id FROM chart_of_accounts WHERE account_code = '6-100'), 100000, 0),
       (currval('journal_headers_header_id_seq'), (SELECT account_id FROM chart_of_accounts WHERE account_code = '1-100'), 0, 100000);
COMMIT;

-- BLOK P3: hapus baris debit sehingga tidak seimbang (harus ERROR "tidak seimbang")
DELETE FROM journal_lines
WHERE header_id = (SELECT header_id FROM journal_headers WHERE reference_no = 'D-001')
  AND debit > 0;

-- BLOK P4: penjualan dengan qty negatif (harus ERROR "Qty -5 tidak valid")
INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('B02', 'SALE', -5);

-- BLOK P5: simpan voucher lewat fungsi RPC formulir web (BERHASIL, keluar ID jurnal)
SELECT simpan_voucher('2026-10-19', 'VKK-001', 'Pembelian alat tulis',
  '[{"akun":"6-100","debit":500000,"kredit":0},
    {"akun":"1-100","debit":0,"kredit":500000}]'::jsonb);

-- BLOK P6: voucher tidak seimbang lewat RPC (harus ERROR "tidak seimbang")
SELECT simpan_voucher('2026-10-19', 'VKK-002', 'Uji tidak seimbang',
  '[{"akun":"6-100","debit":500000,"kredit":0},
    {"akun":"1-100","debit":0,"kredit":400000}]'::jsonb);

-- BLOK P7: lihat voucher yang tersimpan (VKK-001 ada, VKK-002 tidak ada)
SELECT h.reference_no, h.description, a.account_name, l.debit, l.credit
FROM journal_lines l
JOIN journal_headers h USING (header_id)
JOIN chart_of_accounts a USING (account_id)
WHERE h.reference_no LIKE 'VKK-%'
ORDER BY l.line_id;
