-- =============================================================================
-- L16 LAB - Query JSON with dot notation and FLATTEN
-- Section 3: Tables, Views & Semi-Structured Data
-- Self-contained (no S3). Runs in its own JSON_LAB database.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS JSON_LAB;
CREATE SCHEMA IF NOT EXISTS JSON_LAB.PUBLIC;
USE SCHEMA JSON_LAB.PUBLIC;

-- 1. A table with a single VARIANT column to hold raw JSON order events,
--    each with a nested customer object and an array of line items.
CREATE OR REPLACE TABLE raw_order_events (v VARIANT);

INSERT INTO raw_order_events
SELECT PARSE_JSON(column1)
FROM VALUES
('{
   "order_id": 2001,
   "customer": { "name": "Ava Patel", "country": "US", "vip": true },
   "items": [
     { "sku": "A-100", "qty": 2, "price": 19.99 },
     { "sku": "B-220", "qty": 1, "price": 49.50 }
   ]
 }'),
('{
   "order_id": 2002,
   "customer": { "name": "Liam Chen", "country": "GB", "vip": false },
   "items": [
     { "sku": "C-310", "qty": 3, "price": 9.00 },
     { "sku": "A-100", "qty": 1, "price": 19.99 },
     { "sku": "D-415", "qty": 5, "price": 4.25 }
   ]
 }'),
('{
   "order_id": 2003,
   "customer": { "name": "Mia Garcia", "country": "ES", "vip": true },
   "items": [
     { "sku": "B-220", "qty": 2, "price": 49.50 }
   ]
 }');

SELECT * FROM raw_order_events;

-- 2. Reach into the JSON with dot notation, and cast to real SQL types with ::
SELECT
    v:order_id::INT              AS order_id,
    v:customer.name::STRING      AS customer_name,
    v:customer.country::STRING   AS country,
    v:customer.vip::BOOLEAN      AS is_vip
FROM raw_order_events
ORDER BY order_id;

-- 3. Bracket notation reaches array elements by position (first item here).
SELECT
    v:order_id::INT                AS order_id,
    v:items[0].sku::STRING         AS first_sku,
    v:items[0].qty::INT            AS first_qty
FROM raw_order_events
ORDER BY order_id;

-- 4. FLATTEN explodes the items array into one row per element, so nested JSON
--    becomes normal relational rows you can group, sum, and join.
SELECT
    v:order_id::INT          AS order_id,
    f.value:sku::STRING      AS sku,
    f.value:qty::INT         AS qty,
    f.value:price::NUMBER(10,2) AS price,
    (f.value:qty::INT * f.value:price::NUMBER(10,2)) AS line_total
FROM raw_order_events,
     LATERAL FLATTEN(input => v:items) f
ORDER BY order_id, sku;

-- 5. Now it behaves like a table: total revenue per order from the flattened rows.
SELECT
    v:order_id::INT AS order_id,
    SUM(f.value:qty::INT * f.value:price::NUMBER(10,2)) AS order_total
FROM raw_order_events,
     LATERAL FLATTEN(input => v:items) f
GROUP BY order_id
ORDER BY order_id;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP TABLE IF EXISTS raw_order_events;
