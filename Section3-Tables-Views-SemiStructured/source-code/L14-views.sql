-- =============================================================================
-- L14 LAB - Build standard, materialized, and secure views
-- Section 3: Tables, Views & Semi-Structured Data
-- PREREQ: run L12 first (this uses SNOWFLAKE_LABS.RETAIL.customers / orders).
-- Materialized views require Enterprise edition (Snowflake trials are Enterprise).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
USE SCHEMA SNOWFLAKE_LABS.RETAIL;

-- 1. STANDARD VIEW: just a stored query. No storage, always current. Runs fresh
--    every time. Here we join orders to customers behind a clean name.
CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    o.order_id,
    c.name        AS customer_name,
    c.country,
    o.status,
    o.amount,
    o.order_ts
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id;

SELECT * FROM v_order_summary ORDER BY order_id;

-- 2. MATERIALIZED VIEW: results are precomputed and stored, kept fresh
--    automatically. Restrictions: single table, no joins, aggregates ok.
--    So we aggregate revenue per status off the single orders table.
CREATE OR REPLACE MATERIALIZED VIEW mv_revenue_by_status AS
SELECT
    status,
    SUM(amount)  AS total_revenue,
    COUNT(*)     AS order_count
FROM orders
GROUP BY status;

SELECT * FROM mv_revenue_by_status ORDER BY total_revenue DESC;

-- 3. SECURE VIEW: hides its own definition from users who can only query it,
--    and disables optimizations that could leak the underlying data.
CREATE OR REPLACE SECURE VIEW v_customer_contact_secure AS
SELECT customer_id, name, country
FROM customers;

SELECT * FROM v_customer_contact_secure ORDER BY customer_id;

-- 4. Prove the difference. SHOW VIEWS lists all of them (it includes
--    materialized views too): read the IS_MATERIALIZED column (true only for
--    mv_revenue_by_status) and the IS_SECURE column (true only for the secure
--    view). Do NOT filter with LIKE 'v_%', that would hide the mv_ matview.
SHOW VIEWS IN SCHEMA SNOWFLAKE_LABS.RETAIL;
SELECT GET_DDL('view', 'v_order_summary');             -- standard: definition visible
SELECT GET_DDL('view', 'v_customer_contact_secure');   -- secure: owner sees it; others cannot

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP VIEW IF EXISTS v_order_summary;
-- DROP MATERIALIZED VIEW IF EXISTS mv_revenue_by_status;
-- DROP VIEW IF EXISTS v_customer_contact_secure;
