-- ===== 6_uji_perbaikan.sql =====
-- Jalankan SATU BLOK SAJA setiap kali (sorot blok, lalu F5).

-- BLOK 1: coba akali jurnal POSTED (harus ERROR "Jurnal POSTED tidak boleh diubah")
UPDATE journal_headers
SET posting_status = 'REVERSED', description = 'diubah diam-diam'
WHERE reference_no = 'REV-BKK-001';

-- BLOK 2: buat jurnal DRAFT yang seimbang (BERHASIL)
BEGIN;
INSERT INTO journal_headers (trx_date, reference_no, description)
VALUES ('2026-10-19', 'D-001', 'Uji hapus baris');
INSERT INTO journal_lines (header_id, account_id, debit, credit)
VALUES (currval('journal_headers_header_id_seq'), (SELECT account_id FROM chart_of_accounts WHERE account_code = '6-100'), 100000, 0),
       (currval('journal_headers_header_id_seq'), (SELECT account_id FROM chart_of_accounts WHERE account_code = '1-100'), 0, 100000);
COMMIT;

-- BLOK 3: hapus baris debit sehingga tidak seimbang (harus ERROR "tidak seimbang")
DELETE FROM journal_lines
WHERE header_id = (SELECT header_id FROM journal_headers WHERE reference_no = 'D-001')
  AND debit > 0;

-- BLOK 4: penjualan dengan qty negatif (harus ERROR "Qty -5 tidak valid")
INSERT INTO inventory_transactions (item_id, trx_type, qty) VALUES ('B02', 'SALE', -5);

-- BLOK 5: simpan voucher lewat fungsi RPC formulir web (BERHASIL, keluar ID jurnal)
SELECT simpan_voucher('2026-10-19', 'VKK-001', 'Pembelian alat tulis',
  '[{"akun":"6-100","debit":500000,"kredit":0},
    {"akun":"1-100","debit":0,"kredit":500000}]'::jsonb);

-- BLOK 6: voucher tidak seimbang lewat RPC (harus ERROR "tidak seimbang")
SELECT simpan_voucher('2026-10-19', 'VKK-002', 'Uji tidak seimbang',
  '[{"akun":"6-100","debit":500000,"kredit":0},
    {"akun":"1-100","debit":0,"kredit":400000}]'::jsonb);

-- BLOK 7: lihat voucher yang tersimpan (VKK-001 ada, VKK-002 tidak ada)
SELECT h.reference_no, h.description, a.account_name, l.debit, l.credit
FROM journal_lines l
JOIN journal_headers h USING (header_id)
JOIN chart_of_accounts a USING (account_id)
WHERE h.reference_no LIKE 'VKK-%'
ORDER BY l.line_id;
