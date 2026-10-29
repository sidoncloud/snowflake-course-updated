-- =============================================================================
-- PulseMetrics: Snowflake Core Assignment (starter)
--
-- Run in a Snowsight SQL worksheet as ACCOUNTADMIN.
-- The setup block and the data load are done for you. Each TASK section has
-- TODO notes and hints. Write your own SQL under each one.
-- =============================================================================


-- =============================================================================
-- SETUP (given)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS PULSEMETRICS;
CREATE SCHEMA   IF NOT EXISTS PULSEMETRICS.ANALYTICS;
USE SCHEMA PULSEMETRICS.ANALYTICS;


-- =============================================================================
-- TASK 1: Set up compute for loading and for analysts, and cap the spend
-- =============================================================================
-- TODO: Create one warehouse for loading and transforming data, and a separate
--       one for analyst dashboards. Keep both small and cheap when idle.
-- TODO: Create a resource monitor with a small monthly credit quota that
--       notifies first, then suspends, then cuts off. Attach it to both.
-- TODO: Switch your session onto the loading warehouse before you go on.
-- Suggested names: PULSE_ETL_WH, PULSE_BI_WH, PULSE_RM
-- Hint: virtual warehouses and resource monitors, Section 2.



-- =============================================================================
-- TASK 2: Pick the right table type for each table
-- =============================================================================
-- TODO: Create the three tables below. Choose the table type for each one:
--       accounts and subscriptions are data the business cannot lose,
--       usage_events_staging is reloaded on every batch.
-- Hint: permanent, transient and temporary tables, Section 3.
--
-- accounts columns:
--   account_id INT, company_name STRING, plan_tier STRING, country STRING,
--   signed_up_at TIMESTAMP_NTZ, mrr_usd NUMBER(10,2)
--
-- subscriptions columns:
--   account_id INT, plan_tier STRING, seats INT, monthly_price NUMBER(10,2),
--   status STRING, started_at TIMESTAMP_NTZ
--
-- usage_events_staging columns:
--   v VARIANT



-- -----------------------------------------------------------------------------
-- DATA LOAD (given). Run this once your three tables exist.
-- -----------------------------------------------------------------------------

INSERT INTO accounts VALUES
    (301, 'Northwind Analytics',  'ENTERPRISE', 'US', '2026-01-04 09:12:00', 4800.00),
    (302, 'BrightPath SaaS',      'GROWTH',     'GB', '2026-01-06 14:03:00', 1200.00),
    (303, 'Dockside Metrics',     'STARTER',    'CA', '2026-01-09 11:20:00',  199.00),
    (304, 'Verdant Cloud Co',     'GROWTH',     'ES', '2026-01-11 08:45:00', 1200.00),
    (305, 'Helio Systems',        'ENTERPRISE', 'US', '2026-01-15 19:30:00', 6400.00),
    (306, 'Rossi Data Group',     'STARTER',    'IT', '2026-01-18 16:10:00',  199.00),
    (307, 'Haddad Technologies',  'GROWTH',     'AE', '2026-01-22 10:05:00', 1200.00),
    (308, 'Suzuki Intelligence',  'ENTERPRISE', 'JP', '2026-01-25 12:40:00', 5200.00);

INSERT INTO subscriptions VALUES
    (301, 'ENTERPRISE', 40, 4800.00, 'ACTIVE',    '2026-01-04 09:12:00'),
    (302, 'GROWTH',     12, 1200.00, 'ACTIVE',    '2026-01-06 14:03:00'),
    (303, 'STARTER',     3,  199.00, 'ACTIVE',    '2026-01-09 11:20:00'),
    (304, 'GROWTH',     10, 1200.00, 'PAST_DUE',  '2026-01-11 08:45:00'),
    (305, 'ENTERPRISE', 55, 6400.00, 'ACTIVE',    '2026-01-15 19:30:00'),
    (306, 'STARTER',     2,  199.00, 'CANCELLED', '2026-01-18 16:10:00'),
    (307, 'GROWTH',     14, 1200.00, 'ACTIVE',    '2026-01-22 10:05:00'),
    (308, 'ENTERPRISE', 48, 5200.00, 'ACTIVE',    '2026-01-25 12:40:00');

-- Six raw usage events. Each one has a nested features array.
INSERT INTO usage_events_staging
SELECT PARSE_JSON(column1)
FROM VALUES
('{
   "event_id": 9001,
   "account_id": 301,
   "occurred_at": "2026-02-01T10:15:00",
   "features": [
     { "feature": "dashboard_view", "duration_seconds": 420, "credits": 2 },
     { "feature": "export_csv",     "duration_seconds": 15,  "credits": 1 }
   ]
 }'),
('{
   "event_id": 9002,
   "account_id": 302,
   "occurred_at": "2026-02-01T13:42:00",
   "features": [
     { "feature": "api_call",       "duration_seconds": 3,   "credits": 5 },
     { "feature": "api_call",       "duration_seconds": 2,   "credits": 5 },
     { "feature": "dashboard_view", "duration_seconds": 180, "credits": 2 }
   ]
 }'),
('{
   "event_id": 9003,
   "account_id": 303,
   "occurred_at": "2026-02-02T09:05:00",
   "features": [
     { "feature": "dashboard_view", "duration_seconds": 90,  "credits": 2 }
   ]
 }'),
('{
   "event_id": 9004,
   "account_id": 305,
   "occurred_at": "2026-02-03T17:20:00",
   "features": [
     { "feature": "api_call",       "duration_seconds": 4,   "credits": 5 },
     { "feature": "alert_rule",     "duration_seconds": 25,  "credits": 3 },
     { "feature": "export_csv",     "duration_seconds": 12,  "credits": 1 }
   ]
 }'),
('{
   "event_id": 9005,
   "account_id": 307,
   "occurred_at": "2026-02-04T08:33:00",
   "features": [
     { "feature": "dashboard_view", "duration_seconds": 300, "credits": 2 },
     { "feature": "alert_rule",     "duration_seconds": 18,  "credits": 3 }
   ]
 }'),
('{
   "event_id": 9006,
   "account_id": 308,
   "occurred_at": "2026-02-05T21:11:00",
   "features": [
     { "feature": "api_call",       "duration_seconds": 2,   "credits": 5 }
   ]
 }');

-- Quick check: 8 accounts, 8 subscriptions, 6 raw events.
SELECT (SELECT COUNT(*) FROM accounts)             AS accounts,
       (SELECT COUNT(*) FROM subscriptions)        AS subscriptions,
       (SELECT COUNT(*) FROM usage_events_staging) AS raw_events;


-- =============================================================================
-- TASK 3: Turn the nested JSON events into rows analysts can query
-- =============================================================================
-- TODO: Read event_id, account_id and occurred_at out of the VARIANT column
--       and cast them to real SQL types.
-- TODO: Turn the features array into one row per feature line item, and save
--       the result as a table named usage_events_flat with these columns:
--       event_id, account_id, occurred_at, feature, duration_seconds, credits
-- TODO: Show total credits per account from usage_events_flat.
-- Hint: dot notation, the :: cast and FLATTEN, Section 3.



-- =============================================================================
-- TASK 4: Give each team its own view, with billing visible only to finance
-- =============================================================================
-- TODO: Product team: a view that joins usage_events_flat to accounts, so they
--       can see usage per company, plan and country.
-- TODO: Executive dashboard: credits and event count per feature, precomputed
--       so it loads instantly.
-- TODO: Finance: account billing (mrr_usd) in a view whose definition and data
--       stay protected from everyone else.
-- TODO: Prove which view is which with SHOW VIEWS and GET_DDL.
-- Hint: the three kinds of view, Section 3.



-- =============================================================================
-- TASK 5: Recover the deleted data and the dropped table
-- =============================================================================
-- THE INCIDENT (given). An engineer meant to delete a few test events, but the
-- WHERE clause was too broad. Run this to simulate it.
DELETE FROM usage_events_flat
WHERE account_id IN (SELECT account_id FROM accounts WHERE plan_tier = 'STARTER');

-- TODO: Show the table as it was just before that DELETE, then put the missing
--       rows back without duplicating any that are still there.
-- TODO: Then drop usage_events_flat outright and bring it back.
-- Hint: Time Travel and UNDROP, Section 3. You need a way to point at the
--       moment just before the DELETE ran.



-- =============================================================================
-- TASK 6: Give the team a dev copy of the schema for risky changes
-- =============================================================================
-- TODO: Make an instant copy of a single table and prove that changing the copy
--       leaves the original untouched.
-- TODO: Make a copy of the whole ANALYTICS schema named ANALYTICS_DEV.
-- Hint: zero-copy cloning, Section 3.



-- =============================================================================
-- Cleanup (optional, run this when you are done to remove what the lab created).
-- Adjust the warehouse and monitor names if you chose different ones.
-- =============================================================================
-- DROP DATABASE IF EXISTS PULSEMETRICS;
-- DROP WAREHOUSE IF EXISTS PULSE_ETL_WH;
-- DROP WAREHOUSE IF EXISTS PULSE_BI_WH;
-- DROP RESOURCE MONITOR IF EXISTS PULSE_RM;
