-- Script 2 of 2: how to run it.
--
-- The flow mirrors the Data Organizer: clean the raw table, load it, then run
-- the resolve-and-write procedure. Loading goes through do_insert_raw_user,
-- which normalizes the CPFs; do_update_hierarchy matches by CPF and writes
-- parent_id + type onto the existing fsk_users rows. The two SELECTs at the
-- end are the discrepancy report -- what did not resolve.

-- STEP 0 -- Start clean and open the run.
EXEC do_truncate_raw_users;

DECLARE @job_id int;
EXEC start_job @job_id OUTPUT;

-- STEP 1 -- Load the spreadsheet, one call per row. CPFs may come formatted or
--           not ('333.333.333-33' and '33333333333' end up the same after the
--           procedure normalizes them). employee_document is the person;
--           manager_document is the parent.
EXEC do_insert_raw_user 'Bruna',  'Souza',   '111.111.111-11', 'Thiago', 'Lima', '33333333333',    'SalesRepresentative';
EXEC do_insert_raw_user 'Carlos', 'Andrade', '22222222222',    'Thiago', 'Lima', '333.333.333-33', 'SalesRepresentative';
EXEC do_insert_raw_user 'Thiago', 'Lima',    '333.333.333-33', NULL,     NULL,   NULL,             'Coordinator';

-- STEP 2 -- Resolve by CPF and write the hierarchy onto fsk_users.
EXEC do_update_hierarchy;

-- STEP 3 -- Discrepancy: employees whose CPF matched nobody in fsk_users.
--           These were not written; they need registering first, at the source.
SELECT DISTINCT raw_user.employee_first_name, raw_user.employee_last_name, raw_user.employee_document
FROM raw_users AS raw_user
WHERE raw_user.employee_document IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM fsk_users
    WHERE register_type = 'CPF'
      AND RIGHT('00000000000' + REPLACE(REPLACE(REPLACE(unique_register_id, '.', ''), '-', ''), ' ', ''), 11) = raw_user.employee_document
  );

-- STEP 4 -- Discrepancy: rows whose manager CPF matched nobody. Flags per
--           employee which parent did not resolve (or is missing).
SELECT raw_user.employee_first_name, raw_user.employee_last_name, raw_user.manager_first_name, raw_user.manager_last_name, raw_user.manager_document
FROM raw_users AS raw_user
WHERE raw_user.manager_document IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM fsk_users
    WHERE register_type = 'CPF'
      AND RIGHT('00000000000' + REPLACE(REPLACE(REPLACE(unique_register_id, '.', ''), '-', ''), ' ', ''), 11) = raw_user.manager_document
  );

EXEC finish_job @job_id;
GO
