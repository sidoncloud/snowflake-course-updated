-- =============================================================================
-- Kestrel Cold Chain: External Functions and Iceberg Assignment (starter)
--
-- Run in a Snowsight SQL worksheet as ACCOUNTADMIN.
-- The setup block and the shipment data are done for you. Each TASK section
-- has TODO notes and hints. Some of the work happens in the AWS console.
-- =============================================================================


-- =============================================================================
-- SETUP (given)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS KESTREL_WH
  WAREHOUSE_SIZE      = 'XSMALL'
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Kestrel Cold Chain: external functions and Iceberg assignment';
USE WAREHOUSE KESTREL_WH;

CREATE DATABASE IF NOT EXISTS KESTREL;
CREATE SCHEMA   IF NOT EXISTS KESTREL.SUSTAINABILITY;
USE SCHEMA KESTREL.SUSTAINABILITY;

-- The AWS region of your Snowflake account. Your S3 bucket for Task 4 must be
-- in this same region: AWS_US_EAST_1 is us-east-1, AWS_EU_WEST_1 is eu-west-1.
SELECT CURRENT_REGION();

-- Ten freight lanes out of Rotterdam and Amsterdam, plus one drone pilot lane
-- the emissions service does not support yet.
CREATE OR REPLACE TABLE lanes (
    lane_id        STRING,
    origin         STRING,
    destination    STRING,
    transport_mode STRING,
    distance_km    NUMBER(8,1)
);
INSERT INTO lanes VALUES
  ('L01', 'Rotterdam', 'Antwerp',   'ROAD',    100),
  ('L02', 'Rotterdam', 'Munich',    'ROAD',    830),
  ('L03', 'Rotterdam', 'Warsaw',    'RAIL',   1190),
  ('L04', 'Rotterdam', 'Milan',     'RAIL',   1080),
  ('L05', 'Rotterdam', 'Dublin',    'SEA',    1270),
  ('L06', 'Rotterdam', 'New York',  'SEA',    6200),
  ('L07', 'Rotterdam', 'Singapore', 'SEA',   15300),
  ('L08', 'Amsterdam', 'Dubai',     'AIR',    5150),
  ('L09', 'Amsterdam', 'New York',  'AIR',    5860),
  ('L10', 'Amsterdam', 'Singapore', 'AIR',   10500),
  ('L11', 'Rotterdam', 'Delft',     'DRONE',    25);

-- 480 Q3 2026 shipments, generated with fixed formulas so everyone gets the
-- same numbers: lanes cycle L01 to L10, every third shipment is refrigerated
-- (reefer), air cargo is 50 to 499 kg, everything else 200 to 1999 kg.
CREATE OR REPLACE TABLE shipments AS
WITH seq AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS n
    FROM TABLE(GENERATOR(ROWCOUNT => 480))
)
SELECT 'KCC-' || LPAD(n + 1, 5, '0')                       AS shipment_id,
       'L' || LPAD(MOD(n, 10) + 1, 2, '0')                 AS lane_id,
       DATEADD('day', MOD(n * 7, 92), '2026-07-01'::DATE)  AS ship_date,
       IFF(MOD(n, 10) >= 7,
           50 + MOD(n * 13, 450),
           200 + MOD(n * 37, 1800))::NUMBER(8,1)           AS weight_kg,
       MOD(n, 3) = 0                                       AS reefer
FROM seq;

-- Three bad records every real system has: a drone pilot shipment, a missing
-- weight, and a negative weight typed by mistake.
INSERT INTO shipments VALUES
  ('KCC-90001', 'L11', '2026-09-14',  4.5, FALSE),
  ('KCC-90002', 'L02', '2026-09-15', NULL, TRUE),
  ('KCC-90003', 'L06', '2026-09-16', -750, FALSE);

-- 483 shipments across 5 modes.
SELECT l.transport_mode, COUNT(*) AS shipments, SUM(s.weight_kg) AS total_weight_kg
FROM shipments s JOIN lanes l ON l.lane_id = s.lane_id
GROUP BY l.transport_mode
ORDER BY l.transport_mode;


-- =============================================================================
-- TASK 1: Put the calculator behind an endpoint only Snowflake can call
-- =============================================================================
-- AWS side (see the README for the high-level list):
-- TODO: Deploy lambda/lambda_function.py as a Lambda function and test it with
--       lambda/test_event.json before Snowflake touches it.
-- TODO: Put it behind an HTTPS endpoint that rejects unsigned callers.
-- TODO: Create an IAM role that Snowflake will assume, allowed to call only
--       that one endpoint.
-- Snowflake side:
-- TODO: Tell Snowflake which role to assume and which URLs it may call.
-- TODO: Lock the role's trust policy so only YOUR Snowflake account can use it.
-- Hint: external functions, Section 8. The same two-sided trust setup as a
--       storage integration in Section 5.



-- =============================================================================
-- TASK 2: Score every shipment from Snowflake, with no maths copied into SQL
-- =============================================================================
-- The service takes (transport_mode, distance_km, weight_kg, reefer) and
-- returns a JSON object per row. Read lambda/lambda_function.py for the exact
-- request and response shape.
-- TODO: Make the service callable as a function in SQL, sending at most 100
--       rows per request.
-- TODO: Check it with one ROAD, one AIR and one DRONE leg.
-- TODO: Score all 483 shipments in one pass and keep the results, so you never
--       pay to call the service twice for the same rows.
-- TODO: Show how Snowflake split the rows into requests.
-- Hint: external functions and VARIANT results, Sections 8 and 3.



-- =============================================================================
-- TASK 3: Set bad records aside so they don't fail the whole run
-- =============================================================================
-- TODO: Count how many shipments scored and how many were rejected.
-- TODO: Build a quarantine list for the data owners: one row per rejected
--       shipment with the reason the service gave.
-- Hint: look at what the service returns for a row it can't score.



-- =============================================================================
-- TASK 4: Store the results in your own S3, in a format other tools can read
-- =============================================================================
-- AWS side:
-- TODO: Create an S3 bucket in your Snowflake region, and an IAM role that can
--       read, write, list and delete only under one prefix of it.
-- Snowflake side:
-- TODO: Point Snowflake at that bucket and role, lock the trust policy to your
--       account, and verify Snowflake can really use the bucket.
-- TODO: Create a Snowflake-managed table in an open table format in your
--       bucket, named shipment_emissions, and load every shipment that scored
--       cleanly: the shipment and lane details plus tonne_km, co2e_kg,
--       factor_kg_per_tkm, method and scored_at.
-- TODO: Find the table's data and metadata files in your bucket.
-- Hint: Iceberg tables and external volumes, Section 8.



-- =============================================================================
-- TASK 5: Handle corrections and late shipments, and show the value before a fix
-- =============================================================================
-- What happened after the first report:
--   KCC-00042 was re-weighed by the warehouse at 1650 kg. Recompute its CO2e
--   with the service, inside the change itself.
--   KCC-00100 was cancelled before it shipped.
--   The late and corrected records below arrived: the two bad weights are
--   fixed, two new shipments arrive, and KCC-00007 is resent because it was
--   not refrigerated after all.

-- LATE RECORDS (given). Run this when you reach this task.
CREATE OR REPLACE TABLE late_shipments (
    shipment_id STRING, lane_id STRING, ship_date DATE, weight_kg NUMBER(8,1), reefer BOOLEAN);
INSERT INTO late_shipments VALUES
  ('KCC-90002', 'L02', '2026-09-15',  980, TRUE),
  ('KCC-90003', 'L06', '2026-09-16',  750, FALSE),
  ('KCC-00481', 'L09', '2026-09-30',  320, TRUE),
  ('KCC-00482', 'L03', '2026-09-30', 1400, FALSE),
  ('KCC-00007', 'L07', '2026-08-12',  422, FALSE);

-- TODO: Apply the correction to KCC-00042 and remember which statement did it.
-- TODO: Remove the cancelled shipment.
-- TODO: Apply the late records in one statement: update the ones that already
--       exist, insert the new ones, and score each one with the service.
-- TODO: Show KCC-00042 before and after the correction, side by side.
-- Hint: UPDATE, DELETE and MERGE on Iceberg tables, Section 8, and Time Travel,
--       Section 3.



-- =============================================================================
-- TASK 6: Publish a monthly report for the auditors
-- =============================================================================
-- The report: one row per month and lane, with shipments, tonne_km, co2e_kg and
-- grams of CO2e per tonne-km. The auditors read it with their own tools, so it
-- must also live in your bucket in the same open format, and stay fresh
-- without anyone rerunning it.
-- TODO: Show which transport mode really drives Kestrel's emissions.
-- TODO: Build the monthly report.
-- Hint: dynamic tables, Section 6, combined with Iceberg tables, Section 8.



-- =============================================================================
-- Cleanup (optional, run this when you are done to remove what the lab created).
-- Drop the Iceberg tables and the database, then your integration and external
-- volume (DROP INTEGRATION, DROP EXTERNAL VOLUME), then the warehouse:
-- DROP DATABASE IF EXISTS KESTREL;
-- DROP WAREHOUSE IF EXISTS KESTREL_WH;
-- Then, in AWS: delete the API, the Lambda function and its log group, the IAM
-- roles, and empty and delete your bucket.
-- =============================================================================
