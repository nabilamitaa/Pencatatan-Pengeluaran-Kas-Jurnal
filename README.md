# UTS Pemrograman / Coding Akuntansi — Modul General Ledger, Persediaan, dan Voucher Kas Keluar

| | |
|---|---|
| Nama | Nabila Amita Putri |
| NIM | 12030124120014 |
| Kelas | D |
| Mata Kuliah | Pemrograman / Coding — Departemen Akuntansi FEB Universitas Diponegoro |
| Dosen Pengampu | Totok Dewayanto |
| Teknologi | PostgreSQL 18 (pgAdmin 4), Supabase, HTML + Tailwind CSS + JavaScript, Gemini Canvas, NotebookLM |

Repositori ini berisi seluruh artefak jawaban UTS: skema basis data, trigger dan fungsi SQL, formulir web, log prompt AI, dan tangkapan layar pengujian. Penjelasan lengkap setiap soal ada di lembar jawaban (PDF).

---

## 1. Isi folder

| File | Isi | Soal |
|---|---|---|
| `soal1.sql` | Tabel `chart_of_accounts`, `journal_headers`, `journal_lines` dengan PRIMARY KEY, FOREIGN KEY (ON DELETE RESTRICT), CHECK constraint, dan trigger pengecek Debit = Kredit | 1.2 |
| `soal2.sql` | Tabel persediaan dari soal, akun Persediaan/HPP/Utang, trigger `trg_update_stock_and_journal()`, serta contoh `SELECT ... FOR UPDATE` dan `SERIALIZABLE` | 2.1, 2.2 |
| `soal3.sql` | Kolom audit (`created_by`, `created_at`, `hash_checksum`), kunci jurnal POSTED, fungsi `post_journal`, `reverse_journal` (storno), `hitung_hash`, `simpan_voucher` (RPC), dan query verifikasi integritas | 3.2 |
| `form.html` | Formulir Voucher Kas Keluar dengan indikator seimbang otomatis dan koneksi ke Supabase | 3.1a |
| `uji_jawaban.sql` | Skrip pengujian lengkap untuk database baru (dijalankan per blok) | Semua |
| `5_perbaikan_akhir.sql` | Pembaruan untuk database lama: pengecekan saat baris dihapus, validasi qty, kunci REVERSED diperketat, fungsi `simpan_voucher` | 1.2, 2.1, 3.2 |
| `6_uji_perbaikan.sql` | Skrip pengujian untuk perbaikan di atas | 1.2, 2.1, 3.1a, 3.2 |
| `supabase_semua.sql` | Seluruh SQL dalam satu file untuk Supabase SQL Editor, termasuk data akun contoh dan izin akses RPC | 3.1a |
| `prompt_log.txt` | Log prompt dan jawaban Gemini Canvas serta NotebookLM | 3.1a, 3.1b |
| `screenshot/` | Tangkapan layar hasil pengujian | Lampiran |

---

## 2. Cara menjalankan di PostgreSQL (pgAdmin)

1. Buat database baru, misalnya `uts_coding`, lalu buka **Query Tool** pada database tersebut.
2. Jalankan file berikut **berurutan**, masing-masing dengan F5:
   1. `soal1.sql`
   2. `soal2.sql`
   3. `soal3.sql`
3. Buka `uji_jawaban.sql`. Sorot **satu blok** (dari baris `-- BLOK ...` sampai sebelum blok berikutnya), lalu tekan F5. Ulangi untuk setiap blok.

> **Penting:** jangan menjalankan beberapa blok sekaligus. Jika salah satu perintah dalam sorotan menghasilkan ERROR, pgAdmin membatalkan **semua** perintah dalam sorotan tersebut.

Blok yang diberi keterangan **"harus ERROR"** memang dirancang gagal. Error tersebut membuktikan aturan bisnis bekerja.

---

## 3. Ringkasan hasil pengujian

| Uji | Skenario | Hasil yang diharapkan |
|---|---|---|
| 1.2 | Baris jurnal debit 0 dan kredit 0 | Ditolak (CHECK constraint) |
| 1.2 | Jurnal debit Rp500.000, kredit Rp400.000 | Ditolak: "Jurnal ... tidak seimbang" |
| 1.2 | Menghapus satu baris dari jurnal seimbang | Ditolak: "Jurnal ... tidak seimbang" |
| 2.1 | Menjual 2 unit saat stok 1 | Ditolak: "Stok ... tidak cukup" |
| 2.1 | Penjualan dengan qty negatif | Ditolak: "Qty ... tidak valid" |
| 2.1 | Pembelian dan penjualan normal | Stok berubah dan jurnal Persediaan/HPP terbentuk otomatis |
| 3.2 | Mengubah atau menghapus jurnal POSTED | Ditolak: "Jurnal POSTED tidak boleh diubah/dihapus" |
| 3.2 | Mengubah baris debit/kredit jurnal POSTED | Ditolak |
| 3.2 | Mengakali status REVERSED sambil mengubah keterangan | Ditolak |
| 3.2 | Koreksi dengan `reverse_journal` | Jurnal asal REVERSED, jurnal storno POSTED, `data_utuh = true` |
| 3.1a | Simpan voucher seimbang lewat `simpan_voucher` | Berhasil, mengembalikan ID jurnal |
| 3.1a | Simpan voucher tidak seimbang | Ditolak oleh database |

---

## 4. Formulir web dan Supabase (Soal 3.1a)

Formulir dibuat dengan Gemini Canvas, lalu dikembangkan dengan (1) pembulatan dua desimal untuk menghindari galat floating point dan (2) koneksi ke Supabase melalui RPC `simpan_voucher`.

**Cara kerja singkat:**
- Total Debit dan Total Kredit dihitung otomatis setiap angka diketik.
- Tombol **Simpan Voucher** hanya aktif jika Total Debit = Total Kredit (asas *zero-discrepancy*).
- Saat disimpan, data dikirim ke fungsi `simpan_voucher` di database. Database memeriksa ulang keseimbangan, sehingga data yang dikirim tanpa melalui formulir tetap ditolak jika tidak seimbang.

**Cara menyambungkan ke Supabase:**
1. Buat proyek di [supabase.com](https://supabase.com).
2. Buka **SQL Editor**, tempel seluruh isi `supabase_semua.sql`, lalu klik **Run**.
3. Buka **Project Settings → API**, lalu salin **Project URL** dan **publishable/anon key**.
4. Buka `form.html` di editor teks, isi `SUPABASE_URL` dan `SUPABASE_ANON_KEY`, lalu simpan.
5. Buka `form.html` di browser dan isi voucher dengan kode akun, misalnya `6-200` (Beban ATK) di debit dan `1-100` (Kas) di kredit.

Jangan pernah menaruh kunci **service_role/secret** di `form.html`. Formulir hanya diberi izin memanggil fungsi `simpan_voucher`, bukan mengakses tabel secara langsung.

---

## 5. Ringkasan desain per soal

**Soal 1 — Arsitektur data dan asas berpasangan.** Model Header-Line (satu header per bukti transaksi, banyak baris debit/kredit) memenuhi 3NF dan memudahkan audit trail. Keseimbangan Debit = Kredit ditegakkan di database melalui constraint trigger yang ditunda sampai COMMIT, bukan hanya di frontend.

**Soal 2 — Persediaan perpetual.** Trigger `BEFORE INSERT` memvalidasi qty, mengunci baris barang (`FOR UPDATE`), memperbarui stok, menolak stok negatif, dan membuat jurnal Persediaan/HPP dalam satu transaksi. Race condition dua kasir dicegah dengan row locking; alternatifnya isolasi `SERIALIZABLE` dengan retry.

**Soal 3 — Web, AI, dan audit trail.** Formulir web menjaga keseimbangan di sisi pengguna, NotebookLM dipakai untuk memverifikasi kesesuaian dengan PSAK 207 Laporan Arus Kas, dan database mengunci jurnal POSTED. Koreksi dilakukan dengan jurnal pembalik (storno), serta setiap jurnal memiliki `created_by`, `created_at`, dan `hash_checksum` SHA-256 untuk verifikasi integritas.

---

## 6. Catatan

- Kode diuji di PostgreSQL 18 (pgAdmin 4). Fungsi `sha256()` membutuhkan PostgreSQL 11 atau lebih baru.
- File `3_update_perbaikan.sql` dan `4_uji_ulang.sql` (jika ada) adalah tahap pembaruan sebelumnya. Untuk database baru cukup gunakan `soal1.sql`, `soal2.sql`, `soal3.sql`, dan `uji_jawaban.sql`.
- Kolom `created_by` pada voucher dari formulir tercatat sebagai pemilik fungsi (`postgres`), karena purwarupa belum memakai login pengguna. Pada sistem produksi, nilai ini diganti dengan `auth.uid()` dari Supabase Auth.
