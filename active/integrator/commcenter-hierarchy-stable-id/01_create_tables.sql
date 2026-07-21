-- Script 1 of 2: tables and procedures.
--
-- fsk_users ALREADY EXISTS -- it is the resolved users table and is NOT
-- created here. The only new table is raw_users, the source landing area,
-- truncated at the start of every run. Modeled on the Data Organizer
-- (docs/mssql-data_organizer): a raw cli_* table plus procedures that resolve
-- it against fsk_* by a stable id and write to fsk_*.
--
-- Matching is by CPF, not by name. fsk_users keeps the CPF in
-- unique_register_id (register_type = 'CPF') with a UNIQUE index, so a match
-- is unambiguous -- no homonym false-merge, no fan-out, no abbreviation guess.
-- The CPF is normalized to canonical 11 digits by do_insert_raw_user before it
-- is stored, so employee_document / manager_document already hold the clean
-- value. The name columns are kept only for the discrepancy report.
--
-- Conventions match the integrator MSSQL schema: datetime + GETUTCDATE(),
-- int IDENTITY(1,1), varchar, bracketed identifiers.

-- Job log. One row per run: started_at at start, finished_at at end.
CREATE TABLE [jobs] (
  [id] int IDENTITY(1,1) NOT NULL,
  [started_at] datetime NOT NULL,
  [finished_at] datetime NULL,
  CONSTRAINT [PK_jobs] PRIMARY KEY CLUSTERED ([id] ASC)
)
GO

-- Raw source. The hierarchy spreadsheet rows plus the manager CPF. Truncated
-- at the start of each run. employee_document / manager_document store the CPF
-- already normalized (11 digits, no punctuation) by do_insert_raw_user.
CREATE TABLE [raw_users] (
  [id] int IDENTITY(1,1) NOT NULL,
  [employee_first_name] varchar(50) COLLATE SQL_Latin1_General_Cp1_CI_AI NULL,
  [employee_last_name] varchar(50) COLLATE SQL_Latin1_General_Cp1_CI_AI NULL,
  [employee_document] varchar(11) NULL,
  [manager_first_name] varchar(50) COLLATE SQL_Latin1_General_Cp1_CI_AI NULL,
  [manager_last_name] varchar(50) COLLATE SQL_Latin1_General_Cp1_CI_AI NULL,
  [manager_document] varchar(11) NULL,
  [role] varchar(25) NULL,
  [created_at] datetime NOT NULL,
  CONSTRAINT [PK_raw_users] PRIMARY KEY CLUSTERED ([id] ASC)
)
GO

-- do_truncate_raw_users: empties raw_users so a run always starts clean.
-- Same shape as the Data Organizer's do_truncate_users.
IF OBJECT_ID ( 'dbo.do_truncate_raw_users', 'P' ) IS NOT NULL
  DROP PROCEDURE dbo.do_truncate_raw_users;
GO

CREATE PROCEDURE do_truncate_raw_users
AS
BEGIN
  TRUNCATE TABLE raw_users;
END;
GO

-- do_insert_raw_user: the single entry point to load one row into raw_users.
-- It normalizes each CPF -- strips '.', '-' and spaces, then left-pads to 11
-- digits -- and stores the canonical value, so the caller passes the CPF in
-- whatever shape the spreadsheet has it.
IF OBJECT_ID ( 'dbo.do_insert_raw_user', 'P' ) IS NOT NULL
  DROP PROCEDURE dbo.do_insert_raw_user;
GO

CREATE PROCEDURE do_insert_raw_user(
  @employee_first_name varchar(50),
  @employee_last_name varchar(50),
  @employee_document varchar(20),
  @manager_first_name varchar(50) = NULL,
  @manager_last_name varchar(50) = NULL,
  @manager_document varchar(20) = NULL,
  @role varchar(25) = NULL
) AS
BEGIN
  DECLARE @normalized_employee_document varchar(11);
  DECLARE @normalized_manager_document varchar(11);

  SET @normalized_employee_document = RIGHT('00000000000' + REPLACE(REPLACE(REPLACE(@employee_document, '.', ''), '-', ''), ' ', ''), 11);
  SET @normalized_manager_document = RIGHT('00000000000' + REPLACE(REPLACE(REPLACE(@manager_document, '.', ''), '-', ''), ' ', ''), 11);

  INSERT INTO raw_users (employee_first_name, employee_last_name, employee_document, manager_first_name, manager_last_name, manager_document, role, created_at)
  VALUES (@employee_first_name, @employee_last_name, @normalized_employee_document, @manager_first_name, @manager_last_name, @normalized_manager_document, @role, GETUTCDATE());
END
GO

-- do_update_hierarchy: resolves raw_users against fsk_users by CPF and writes
-- the hierarchy onto fsk_users -- parent_id from the manager CPF and type from
-- the role. Set-based (the write is two columns; the Data Organizer's cursor
-- exists only for its multi-column diff). fsk_users is normalized inline
-- because it cannot be altered and its unique_register_id is not guaranteed
-- clean; raw_users is already normalized by do_insert_raw_user. Only EXISTING
-- users are updated: a person not yet in fsk_users cannot be created here (the
-- hierarchy sheet lacks the email/city/register data fsk_users requires) --
-- those surface in the discrepancy report instead.
IF OBJECT_ID ( 'dbo.do_update_hierarchy', 'P' ) IS NOT NULL
  DROP PROCEDURE dbo.do_update_hierarchy;
GO

CREATE PROCEDURE do_update_hierarchy
AS
BEGIN
  UPDATE employee
  SET
    parent_id = manager.id,
    type = raw_user.role,
    updated_at = GETUTCDATE()
  FROM fsk_users AS employee
  JOIN raw_users AS raw_user
    ON RIGHT('00000000000' + REPLACE(REPLACE(REPLACE(employee.unique_register_id, '.', ''), '-', ''), ' ', ''), 11) = raw_user.employee_document
   AND employee.register_type = 'CPF'
  LEFT JOIN fsk_users AS manager
    ON RIGHT('00000000000' + REPLACE(REPLACE(REPLACE(manager.unique_register_id, '.', ''), '-', ''), ' ', ''), 11) = raw_user.manager_document
   AND manager.register_type = 'CPF';
END
GO

-- start_job: open a run. Returns the new job id through an OUTPUT parameter --
-- SCOPE_IDENTITY() read by the caller after EXEC would be NULL, because the
-- INSERT runs in the procedure's own scope.
CREATE PROCEDURE start_job(
  @job_id int OUTPUT
) AS
BEGIN
  INSERT INTO jobs (started_at)
  VALUES (GETUTCDATE());

  SET @job_id = SCOPE_IDENTITY();
END
GO

-- finish_job: close a run.
CREATE PROCEDURE finish_job(
  @job_id int
) AS
BEGIN
  UPDATE jobs SET finished_at = GETUTCDATE() WHERE id = @job_id;
END
GO
