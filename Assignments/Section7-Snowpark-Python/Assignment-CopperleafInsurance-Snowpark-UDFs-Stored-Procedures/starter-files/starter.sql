-- =============================================================================
-- Copperleaf Insurance: UDFs, UDTFs and Stored Procedures Assignment (starter)
--
-- Run in a Snowsight SQL worksheet as ACCOUNTADMIN.
-- The setup block and the raw data are done for you. Each TASK section has
-- the business rules, TODO notes and hints. Write your own code under each one.
-- =============================================================================


-- =============================================================================
-- SETUP (given)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS COPPERLEAF_WH
  WAREHOUSE_SIZE      = 'XSMALL'
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Copperleaf Insurance: UDF and stored procedure assignment';
USE WAREHOUSE COPPERLEAF_WH;

CREATE DATABASE IF NOT EXISTS COPPERLEAF;
CREATE SCHEMA   IF NOT EXISTS COPPERLEAF.CLAIMS;
USE SCHEMA COPPERLEAF.CLAIMS;

-- Raw broker claims. Policy numbers come in four styles, dates in five
-- formats, amounts in local currency, and the adjuster notes are free text.
-- LOAD_TS records when each row landed.
CREATE OR REPLACE TABLE claims_raw (
    claim_id          STRING,
    policy_no         STRING,
    claimant          STRING,
    incident_date_raw STRING,
    claim_amount      NUMBER(12,2),
    currency          STRING,
    notes             STRING,
    load_ts           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO claims_raw (claim_id, policy_no, claimant, incident_date_raw, claim_amount, currency, notes) VALUES
  ('CLM-1001', 'POL-004512',  'Amara Okafor',   '2026-03-04',     1850.00, 'USD', 'Rear-ended at a junction, police report filed, two witnesses.'),
  ('CLM-1002', 'pol 4513',    'Ben Hartley',    '03/05/2026',     9400.00, 'GBP', 'Kitchen fire. No police report. Customer paid contractor in cash.'),
  ('CLM-1003', '004514',      'Chen Wei',       'March 6, 2026',   620.00, 'EUR', 'Cracked windscreen from road debris.'),
  ('CLM-1004', 'POL-4515',    'Divya Raman',    '7 Mar 2026',    52000.00, 'AED', 'Water damage, prior claim on same property last year.'),
  ('CLM-1005', 'POL#004516',  'Elena Sokolova', '2026/03/08',    14750.00, 'USD', 'Theft late at night, no witnesses, no police report.'),
  ('CLM-1006', 'pol-4517',    'Farid Haddad',   'last tuesday',    300.00, 'EUR', 'Minor scratch in a car park.'),
  ('CLM-1007', 'POL-0045189', 'Grace Liu',      '2026-03-10',     2600.00, 'GBP', 'Burst pipe, plumber invoice attached.'),
  ('CLM-1008', 'POL-004519',  'Hugo Martin',    '11-Mar-2026',  410000.00, 'INR', 'Two-wheeler collision, police report filed.');

-- Reference exchange rates, one USD rate per currency.
CREATE OR REPLACE TABLE fx_rates (currency_code STRING, rate_to_usd NUMBER(12,6));
INSERT INTO fx_rates VALUES
  ('USD', 1.000000), ('GBP', 1.270000), ('EUR', 1.080000),
  ('AED', 0.272300), ('INR', 0.012000);

SELECT * FROM claims_raw ORDER BY claim_id;


-- =============================================================================
-- TASK 1: Clean up policy numbers and dates, whatever format they arrive in
-- =============================================================================
-- The business rules:
--   Policy number: keep only the digits, pad to six digits, prefix POL-.
--                  More than six digits is invalid, so return NULL.
--                  Example: 'pol 4513' becomes 'POL-004513'.
-- TODO: Write a reusable function for the policy rule.
--   Incident date: parse any reasonable date format into a DATE. Anything that
--                  can't be parsed (such as 'last tuesday') returns NULL.
-- TODO: Write a reusable function for the date rule. Don't write your own date
--       parser, use a third-party Python package.
-- TODO: Test both functions against claims_raw.
-- Hint: Python UDFs and the PACKAGES clause, Section 7.



-- =============================================================================
-- TASK 2: Convert every amount to US dollars and give each claim a severity
-- =============================================================================
-- The business rules:
--   amount_usd = claim_amount x rate_to_usd from fx_rates, rounded to 2 places.
--   Severity:    HIGH if amount_usd is 10000 or more,
--                MEDIUM if 2500 or more, otherwise LOW.
-- TODO: Write a reusable function for the severity rule.
-- TODO: Show every claim with its amount in USD and its severity.
-- Hint: SQL UDFs, Section 7.



-- =============================================================================
-- TASK 3: Pull the fraud signals out of the adjuster notes
-- =============================================================================
-- The business rules (case does not matter). One output row per signal found:
--   NO_POLICE_REPORT  if the notes contain 'no police report' or 'not reported to police'
--   CASH_PAYMENT      if they contain 'in cash' or 'cash only'
--   PRIOR_CLAIM       if they contain 'prior claim' or 'previous claim'
--   NO_WITNESSES      if they contain 'no witnesses' or 'no witness'
--   LATE_NIGHT        if they contain 'late at night'
-- Each output row should carry the signal and the phrase that matched.
-- TODO: Write a function that turns one claim's notes into zero, one or many
--       rows, and call it for every claim in claims_raw.
-- Hint: Python UDTFs, Section 7.



-- =============================================================================
-- TASK 4: Process only new claims, and update resubmitted ones in place
-- =============================================================================
-- TODO: Create the tables the pipeline maintains:
--   claims_clean: claim_id, policy_no, claimant, incident_date, amount_usd,
--                 severity, notes, processed_at
--   claim_flags:  claim_id, flag, matched_phrase, flagged_at
--   Plus whatever you need to remember how far you've already processed.
-- TODO: Write one procedure that takes only the claims that landed since its
--       last run, cleans and scores them with your functions from Tasks 1 to 3,
--       updates a resubmitted claim_id instead of adding a second row,
--       refreshes the fraud flags for that batch, and then records how far it
--       got. Running it twice with no new data must change nothing.
-- TODO: Call it, then call it again to prove the second run does nothing.
-- Hint: Snowpark Python stored procedures, Section 7. Think about a watermark
--       on load_ts, and about MERGE.


-- SECOND BATCH (given). Run this ONLY after your procedure has processed the
-- first 8 claims. Two new claims arrive, plus a broker resubmission of
-- CLM-1003 with a corrected amount and a new note.
INSERT INTO claims_raw (claim_id, policy_no, claimant, incident_date_raw, claim_amount, currency, notes) VALUES
  ('CLM-1009', 'POL-004520', 'Isla Novak',  '2026-03-12', 3100.00, 'EUR', 'Hail damage to roof, previous claim for the same roof in 2024.'),
  ('CLM-1010', 'pol 4521',   'Jamal Brooks','03/13/2026',  780.00, 'USD', 'Laptop dropped, repair quote attached.'),
  ('CLM-1003', '004514',     'Chen Wei',    'March 6, 2026', 2450.00, 'EUR', 'Windscreen and bonnet damage, paid in cash at roadside.');

-- TODO: Run your procedure again and show that CLM-1003 was updated, not
--       duplicated, and that its fraud flags were refreshed.



-- =============================================================================
-- TASK 5: Run it on a schedule, with a record of every run
-- =============================================================================
-- TODO: Make every run of your procedure leave an audit row: when it ran, how
--       many claims it processed, a status, and a short message. A run with
--       nothing new should still leave a row.
-- TODO: Run the procedure every 5 minutes inside Snowflake, trigger one run
--       now, and confirm it succeeded.
-- Hint: tasks, Section 6. The run history doesn't show what a CALL returned,
--       which is why the audit table matters.



-- =============================================================================
-- TASK 6: Give the claims team a queue of claims that need a person
-- =============================================================================
-- The business rule: a claim needs a person if it is HIGH severity, OR has at
-- least one fraud flag, OR failed cleaning (its policy_no or incident_date
-- came back NULL).
-- TODO: Build a view the claims team can query, with one row per claim that
--       needs a person, showing how many flags it has and which ones.
-- Hint: views, Section 3.



-- =============================================================================
-- Cleanup (optional, run this when you are done to remove what the lab created).
-- Suspend your task before dropping the database.
-- =============================================================================
-- DROP DATABASE IF EXISTS COPPERLEAF;
-- DROP WAREHOUSE IF EXISTS COPPERLEAF_WH;
