-- =============================================================================
-- LAB - Write a Python UDF and a UDTF
-- Section 7: Snowpark, Data Engineering in Python
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS SNOWPARK_LAB;
CREATE SCHEMA   IF NOT EXISTS SNOWPARK_LAB.SNOWPARK;
USE SCHEMA SNOWPARK_LAB.SNOWPARK;

-- A small orders table so the lab is self-contained.
CREATE OR REPLACE TABLE orders (
    order_id INT, customer_id INT, amount NUMBER(10,2), status STRING);
INSERT INTO orders VALUES
    (101,1,120.00,'COMPLETED'),(102,1,80.00,'COMPLETED'),
    (103,2,200.00,'COMPLETED'),(105,3,300.00,'COMPLETED'),
    (109,5,220.00,'COMPLETED'),(110,3,40.00,'COMPLETED');

-- 1. A scalar Python UDF. Input columns in, one value out per row. Here it turns
--    an order amount into a tier label. The handler names the Python function.
CREATE OR REPLACE FUNCTION order_tier(amount FLOAT)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'classify'
AS
$$
def classify(amount):
    if amount is None:
        return 'UNKNOWN'
    if amount >= 250:
        return 'GOLD'
    elif amount >= 100:
        return 'SILVER'
    else:
        return 'BRONZE'
$$;

-- Call it like any built-in function, right inside a SELECT.
SELECT order_id, amount, order_tier(amount) AS tier
FROM orders ORDER BY order_id;
--   >= 250 GOLD, >= 100 SILVER, otherwise BRONZE.

-- 2. A Python UDTF. One input row in, many rows out. This one takes a single
--    comma-separated tag string and yields one row per tag. The handler names
--    the class; each value it yields becomes an output row.
CREATE OR REPLACE FUNCTION split_tags(tags STRING)
RETURNS TABLE (tag STRING)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'SplitTags'
AS
$$
class SplitTags:
    def process(self, tags):
        if tags is None:
            return
        for t in tags.split(','):
            t = t.strip()
            if t:
                yield (t,)
$$;

-- Call it with the TABLE keyword and join it against your rows. Each input row
-- expands into as many rows as the function yielded.
SELECT o.order_id, t.tag
FROM (
    SELECT 101 AS order_id, 'vip,priority,gift' AS tags
    UNION ALL
    SELECT 102, 'standard'
) o,
TABLE(split_tags(o.tags)) t
ORDER BY o.order_id, t.tag;
--   Order 101 expands into three rows (gift, priority, vip); order 102 into one.

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP FUNCTION IF EXISTS order_tier(FLOAT);
-- DROP FUNCTION IF EXISTS split_tags(STRING);
-- DROP TABLE IF EXISTS orders;
