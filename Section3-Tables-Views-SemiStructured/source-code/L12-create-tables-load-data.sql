-- =============================================================================
-- L12 LAB - Create tables and load a small dataset
-- Section 3: Tables, Views & Semi-Structured Data
-- Run top to bottom in a Snowsight worksheet.
-- Builds the SNOWFLAKE_LABS.RETAIL schema used by L14 (views) and L18 (time travel).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

-- 1. A home for our data: one database, one schema.
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_LABS;
CREATE SCHEMA   IF NOT EXISTS SNOWFLAKE_LABS.RETAIL;
USE SCHEMA SNOWFLAKE_LABS.RETAIL;

-- 2. A PERMANENT table (the default type): full Time Travel + Fail-safe.
CREATE OR REPLACE TABLE customers (
    customer_id  INT,
    name         STRING,
    email        STRING,
    country      STRING,
    created_at   TIMESTAMP_NTZ
);

-- 3. Load a small dataset by hand so the structure is obvious.
INSERT INTO customers VALUES
    (1, 'Ava Patel',     'ava@example.com',     'US', '2026-01-04 09:12:00'),
    (2, 'Liam Chen',     'liam@example.com',    'US', '2026-01-06 14:03:00'),
    (3, 'Noah Smith',    'noah@example.com',    'GB', '2026-01-09 11:20:00'),
    (4, 'Mia Garcia',    'mia@example.com',     'ES', '2026-01-11 08:45:00'),
    (5, 'Ethan Brown',   'ethan@example.com',   'US', '2026-01-15 19:30:00'),
    (6, 'Sofia Rossi',   'sofia@example.com',   'IT', '2026-01-18 16:10:00'),
    (7, 'Omar Haddad',   'omar@example.com',    'AE', '2026-01-22 10:05:00'),
    (8, 'Hana Suzuki',   'hana@example.com',    'JP', '2026-01-25 12:40:00');

CREATE OR REPLACE TABLE orders (
    order_id     INT,
    customer_id  INT,
    order_ts     TIMESTAMP_NTZ,
    status       STRING,
    amount       NUMBER(10,2)
);

INSERT INTO orders VALUES
    (1001, 1, '2026-02-01 10:15:00', 'SHIPPED',   120.50),
    (1002, 2, '2026-02-01 13:42:00', 'SHIPPED',    89.00),
    (1003, 3, '2026-02-02 09:05:00', 'CANCELLED',  45.25),
    (1004, 1, '2026-02-03 17:20:00', 'SHIPPED',   210.00),
    (1005, 4, '2026-02-03 18:01:00', 'PENDING',    62.75),
    (1006, 5, '2026-02-04 08:33:00', 'SHIPPED',   154.10),
    (1007, 6, '2026-02-05 21:11:00', 'CANCELLED', 300.00),
    (1008, 7, '2026-02-06 11:47:00', 'SHIPPED',    75.90),
    (1009, 2, '2026-02-07 14:25:00', 'PENDING',   132.40),
    (1010, 8, '2026-02-08 16:58:00', 'SHIPPED',    98.20),
    (1011, 3, '2026-02-09 12:03:00', 'SHIPPED',   187.65),
    (1012, 4, '2026-02-10 19:49:00', 'CANCELLED',  54.00);

-- 4. A TRANSIENT table: cheaper, no Fail-safe. Good for reproducible staging.
CREATE OR REPLACE TRANSIENT TABLE orders_staging LIKE orders;
INSERT INTO orders_staging SELECT * FROM orders;

-- 5. Load a bigger set fast with CREATE TABLE AS SELECT, straight from the
--    free sample data Snowflake ships with. No files, no S3 (that is Section 5).
CREATE OR REPLACE TABLE sample_orders AS
SELECT *
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
LIMIT 1000;

-- 6. Sanity checks.
SELECT COUNT(*) AS customer_count FROM customers;
SELECT COUNT(*) AS order_count    FROM orders;
SELECT * FROM orders LIMIT 5;
SELECT COUNT(*) AS sample_count   FROM sample_orders;
SHOW TABLES IN SCHEMA SNOWFLAKE_LABS.RETAIL;
