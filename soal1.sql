-- SOAL 1.2 - DDL General Ledger

CREATE TABLE chart_of_accounts (
    account_id     SERIAL PRIMARY KEY,
    account_code   VARCHAR(10)  NOT NULL UNIQUE,
    account_name   VARCHAR(100) NOT NULL,
    normal_balance CHAR(1)      NOT NULL CHECK (normal_balance IN ('D','K')),
    report_class   VARCHAR(20)  NOT NULL
                   CHECK (report_class IN ('NERACA','LABA_RUGI'))
);

CREATE TABLE journal_headers (
    header_id      SERIAL PRIMARY KEY,
    trx_date       DATE        NOT NULL,
    reference_no   VARCHAR(30) NOT NULL UNIQUE,
    description    TEXT,
    posting_status VARCHAR(10) NOT NULL DEFAULT 'DRAFT'
                   CHECK (posting_status IN ('DRAFT','POSTED','REVERSED'))
);

CREATE TABLE journal_lines (
    line_id    SERIAL PRIMARY KEY,
    header_id  INT NOT NULL REFERENCES journal_headers(header_id)
               ON DELETE RESTRICT,
    account_id INT NOT NULL REFERENCES chart_of_accounts(account_id)
               ON DELETE RESTRICT,
    debit      NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (debit  >= 0),
    credit     NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    CHECK (NOT (debit = 0 AND credit = 0))
);

-- Penegakan asas berpasangan (Debit = Kredit) di level database
CREATE OR REPLACE FUNCTION cek_seimbang() RETURNS TRIGGER AS $$
DECLARE v_id INT := COALESCE(NEW.header_id, OLD.header_id);
BEGIN
    IF (SELECT SUM(debit) <> SUM(credit) FROM journal_lines
        WHERE header_id = v_id) THEN
        RAISE EXCEPTION 'Jurnal % tidak seimbang', v_id;
    END IF;
    RETURN NULL;
END; $$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_cek_seimbang
AFTER INSERT OR UPDATE OR DELETE ON journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION cek_seimbang();
