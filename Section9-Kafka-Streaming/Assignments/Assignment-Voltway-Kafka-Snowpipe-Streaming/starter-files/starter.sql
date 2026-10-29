-- =============================================================================
-- Voltway: Kafka, Snowpipe Streaming and Dynamic Tables Assignment (starter)
--
-- Run in a Snowsight SQL worksheet as ACCOUNTADMIN.
-- The setup block is done for you. Each TASK section has TODO notes and
-- hints. Some of the work happens in your terminal (see the README).
-- =============================================================================


-- =============================================================================
-- SETUP (given)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- This warehouse runs your transformations and queries. Streaming ingestion
-- itself does not need a warehouse.
CREATE WAREHOUSE IF NOT EXISTS VOLTWAY_WH
  WAREHOUSE_SIZE      = 'XSMALL'
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Voltway: transformations and queries';
USE WAREHOUSE VOLTWAY_WH;

CREATE DATABASE IF NOT EXISTS VOLTWAY;
CREATE SCHEMA   IF NOT EXISTS VOLTWAY.STREAMING;
USE SCHEMA VOLTWAY.STREAMING;

-- Reference data: Voltway's five charging stations and their tariffs (USD per kWh).
CREATE OR REPLACE TABLE STATIONS (
  station_id     STRING,
  station_name   STRING,
  city           STRING,
  tariff_per_kwh NUMBER(6,2)
);
INSERT INTO STATIONS VALUES
  ('STN-01', 'Harbor Point Hub',            'Portside',  0.42),
  ('STN-02', 'Ridgeway Retail Park',        'Ridgeway',  0.39),
  ('STN-03', 'Northgate Motorway Services', 'Northgate', 0.55),
  ('STN-04', 'Elm Street Garage',           'Ashford',   0.36),
  ('STN-05', 'Lakeside Business Park',      'Lakeside',  0.45);

SELECT * FROM STATIONS ORDER BY station_id;


-- =============================================================================
-- TASK 1: Give the Kafka connector its own secure login, with least privilege
-- =============================================================================
-- TODO: In your terminal, create a key pair for the connector. Keep the private
--       key on your machine only.
-- TODO: Create a dedicated role, and a user that is a machine identity and
--       can never log in with a password. Register the public key on it.
-- TODO: Give the role only what the connector needs to write into the two
--       landing tables, and nothing more. Prove it with SHOW GRANTS.
-- Hint: key-pair authentication and the connector user, Section 9. Roles and
--       privileges, Section 11.



-- =============================================================================
-- TASK 2: Stream both Kafka topics into Snowflake, with no load jobs
-- =============================================================================
-- Topics: charging_events and charger_status (see the README for the fields).
-- TODO: Create one landing table per topic in VOLTWAY.STREAMING. Decide whether
--       you create them or let the connector do it, and what that means for
--       the privileges in Task 1.
-- TODO: Write the connector configuration, register it with Kafka Connect
--       (http://localhost:8083), and wait until it is RUNNING.
-- TODO: Produce wave 1 (bash 06_produce_events.sh 1) and prove the rows landed:
--       counts, the Kafka metadata on each row, and the streaming channels.
-- Hint: the Kafka connector and Snowpipe Streaming, Section 9. Use key-pair
--       auth, not a password.



-- =============================================================================
-- TASK 3: Turn raw events into sessions, hourly KPIs and charger health
-- =============================================================================
-- What the operations team wants:
--   Clean events:   one typed row per charging event.
--   Sessions:       one row per session_id with charger, station, start, end,
--                   kWh delivered, duration and revenue (kWh x station tariff).
--                   A session with no start yet, or no stop yet, must still
--                   show up with a status that says so.
--   Hourly KPIs:    per station, per hour: completed sessions, kWh, revenue
--                   and average session length.
--   Charger health: the latest status of every charger.
-- TODO: Build these so they keep themselves fresh, no more than about a minute
--       behind the landing tables, with no tasks or schedules to manage.
-- Hint: dynamic tables and TARGET_LAG, Section 6. JSON dot notation, Section 3.
--       Dynamic tables read their sources incrementally, which needs change
--       tracking on the landing tables. Think about when that gets switched on.



-- =============================================================================
-- TASK 4: Make sure duplicate events don't inflate the numbers
-- =============================================================================
-- Wave 2 re-sends some morning events that already landed.
-- TODO: Produce wave 2 (bash 06_produce_events.sh 2).
-- TODO: Show how many events landed versus how many distinct events exist.
-- TODO: Make sure each event counts once in everything you built in Task 3.
-- Hint: Kafka delivers at least once. Every event carries an event_id.



-- =============================================================================
-- TASK 5: Keep a broken message from stopping the pipeline
-- =============================================================================
-- Wave 2 also contains one truncated message that is not valid JSON.
-- TODO: Make sure that message doesn't stop the connector, and that it is kept
--       somewhere you can inspect later instead of being silently lost.
-- TODO: Show the connector is still RUNNING after wave 2, and find the broken
--       message and the reason it failed.
-- Hint: connector error handling, Section 9.



-- =============================================================================
-- TASK 6: Let late events correct the numbers already reported
-- =============================================================================
-- Charger CHG-11 lost its network link from 08:45 to 10:40 and uploads what it
-- buffered in wave 3, long after the fact.
-- TODO: Record the numbers before wave 3, produce it
--       (bash 06_produce_events.sh 3), and show which sessions and hours changed.
-- TODO: Make sure a late, older status message never overwrites a newer one
--       in charger health.
-- Hint: dynamic tables recompute from the data, Section 6. Order by when an
--       event happened, not when it arrived.



-- =============================================================================
-- Cleanup (optional, run this when you are done to remove what the lab created).
-- First run bash 11_teardown_kafka.sh in your terminal. Then drop the database,
-- your connector user and role, and the warehouse:
-- DROP DATABASE IF EXISTS VOLTWAY;
-- DROP WAREHOUSE IF EXISTS VOLTWAY_WH;
-- =============================================================================
