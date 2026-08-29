-- =============================================================================
-- SETUP for the Snowpark ML labs (run this FIRST)
-- Section 7: Snowpark, Data Engineering in Python
--
-- WHERE TO RUN THIS: paste it into a Snowsight worksheet and run it as
-- ACCOUNTADMIN, one time, before you run either Python file. It builds the lab
-- environment and generates the source data the training lab reads:
--   - a dedicated database DELIVERY_ML_LAB and a warehouse SNOWPARK_ML_WH
--   - ORDERS: one row per order, the "what was ordered" facts
--   - ORDER_LOGISTICS: one row per order, the "how it was delivered" facts,
--     including DELIVERY_DELAY_MINUTES, the number the model will predict
--
-- The data is generated in SQL with a fixed random seed, so it is identical on
-- every run and needs no file upload. The delay carries a real signal (distance,
-- weight, priority, handoffs, prior delays, weekend, peak hour, courier bias)
-- plus noise, so a model can actually learn it.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- 1. A warehouse and an isolated database for all the ML work.
CREATE WAREHOUSE IF NOT EXISTS SNOWPARK_ML_WH
    WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
CREATE DATABASE IF NOT EXISTS DELIVERY_ML_LAB;
CREATE SCHEMA   IF NOT EXISTS DELIVERY_ML_LAB.PUBLIC;
USE WAREHOUSE SNOWPARK_ML_WH;
USE SCHEMA DELIVERY_ML_LAB.PUBLIC;

-- 2. Generate 5000 raw orders. Each column uses UNIFORM with its own RANDOM seed
--    so the values are independent but reproducible.
CREATE OR REPLACE TABLE gen_base AS
SELECT
    'ORD' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ8()), 6, '0')            AS order_id,
    'CUST' || LPAD(UNIFORM(1, 1200, RANDOM(1)), 5, '0')                   AS customer_id,
    DATEADD(minute, UNIFORM(0, 216000, RANDOM(2)),
            '2026-01-01 06:00:00'::TIMESTAMP_NTZ)                         AS order_ts,
    CASE UNIFORM(1, 5, RANDOM(3))
        WHEN 1 THEN 'NORTH' WHEN 2 THEN 'SOUTH' WHEN 3 THEN 'EAST'
        WHEN 4 THEN 'WEST'  ELSE 'CENTRAL' END                            AS region,
    CASE WHEN UNIFORM(1, 100, RANDOM(4)) <= 60 THEN 'STANDARD'
         WHEN UNIFORM(1, 100, RANDOM(4)) <= 90 THEN 'EXPRESS'
         ELSE 'PRIORITY' END                                             AS priority,
    ROUND(UNIFORM(0.2::FLOAT, 25.0::FLOAT, RANDOM(5)), 2)                 AS package_weight_kg,
    ROUND(UNIFORM(1.0::FLOAT, 120.0::FLOAT, RANDOM(6)), 1)               AS distance_km,
    CASE UNIFORM(1, 5, RANDOM(7))
        WHEN 1 THEN 'SwiftRun' WHEN 2 THEN 'MetroDash' WHEN 3 THEN 'CityHop'
        WHEN 4 THEN 'RapidoLog' ELSE 'NovaShip' END                      AS courier,
    CASE UNIFORM(1, 4, RANDOM(8))
        WHEN 1 THEN 'WH-A1' WHEN 2 THEN 'WH-B2' WHEN 3 THEN 'WH-C3'
        ELSE 'WH-D4' END                                                 AS warehouse,
    UNIFORM(0, 5, RANDOM(9))                                              AS handoffs,
    UNIFORM(0, 8, RANDOM(10))                                             AS prior_delays
FROM TABLE(GENERATOR(ROWCOUNT => 5000));

-- 3. Compute the delivery delay from those facts. This is the signal the model
--    learns: each term is a real driver, and NORMAL adds gaussian noise so the
--    relationship is strong but not perfect.
CREATE OR REPLACE TABLE gen_full AS
SELECT
    g.*,
    CASE WHEN DAYOFWEEK(order_ts) IN (0, 6) THEN 1 ELSE 0 END             AS is_weekend,
    CASE WHEN HOUR(order_ts) BETWEEN 17 AND 20 THEN 1 ELSE 0 END          AS is_peak,
    CASE priority WHEN 'STANDARD' THEN 18 WHEN 'EXPRESS' THEN 7 ELSE 0 END AS priority_add,
    CASE courier
        WHEN 'SwiftRun' THEN -6 WHEN 'MetroDash' THEN 3 WHEN 'CityHop' THEN 11
        WHEN 'RapidoLog' THEN -2 ELSE 7 END                              AS courier_bias
FROM gen_base g;

-- 4. Split the generated facts into the two source tables the labs read.
CREATE OR REPLACE TABLE ORDERS AS
SELECT order_id, customer_id, order_ts, region, priority, package_weight_kg, distance_km
FROM gen_full;

CREATE OR REPLACE TABLE ORDER_LOGISTICS AS
SELECT
    order_id, courier, warehouse, handoffs, prior_delays,
    GREATEST(0, ROUND(
        8
        + distance_km * 0.09
        + package_weight_kg * 1.3
        + priority_add
        + handoffs * 6
        + prior_delays * 2.2
        + is_weekend * 10
        + is_peak * 13
        + courier_bias
        + NORMAL(0, 6, RANDOM(20)), 1)) AS delivery_delay_minutes
FROM gen_full;

-- 5. Drop the scratch tables; the labs only need ORDERS and ORDER_LOGISTICS.
DROP TABLE IF EXISTS gen_base;
DROP TABLE IF EXISTS gen_full;

-- 6. Confirm the source data is ready.
SELECT COUNT(*) AS orders_rows FROM ORDERS;
SELECT COUNT(*) AS logistics_rows FROM ORDER_LOGISTICS;
SELECT order_id, region, priority, ROUND(distance_km, 1) AS distance_km
FROM ORDERS ORDER BY order_id LIMIT 5;
SELECT order_id, courier, handoffs, delivery_delay_minutes
FROM ORDER_LOGISTICS ORDER BY order_id LIMIT 5;

-- Next, open Snowsight Notebooks and create a notebook on DELIVERY_ML_LAB.PUBLIC
-- with warehouse SNOWPARK_ML_WH, adding the packages snowflake-ml-python, xgboost
-- and scikit-learn. Run feature-engineering.py, then ml-train.py, then ml-serve.py.

-- Cleanup (optional, run this when you are done with both Python labs):
--   DROP DATABASE IF EXISTS DELIVERY_ML_LAB;
--   DROP WAREHOUSE IF EXISTS SNOWPARK_ML_WH;
