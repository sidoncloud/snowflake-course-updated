-- =============================================================================
-- Fernridge Market: Multi-Format Ingestion and Pipelines Assignment (starter)
--
-- Run in a Snowsight SQL worksheet as ACCOUNTADMIN.
-- The setup block is done for you. Each TASK section has TODO notes and
-- hints. Write your own SQL under each one.
--
-- The three seller files are in the dataset/ folder of this kit:
--   sellerA_orders.csv, sellerB_orders.json, sellerC_orders.parquet
-- =============================================================================


-- =============================================================================
-- SETUP (given)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS FERNRIDGE_WH
  WAREHOUSE_SIZE      = 'XSMALL'
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Fernridge Market: ingestion and pipeline assignment';
USE WAREHOUSE FERNRIDGE_WH;

CREATE DATABASE IF NOT EXISTS FERNRIDGE;
CREATE SCHEMA   IF NOT EXISTS FERNRIDGE.MARKET;
USE SCHEMA FERNRIDGE.MARKET;


-- =============================================================================
-- TASK 1: Load all three sellers' files into Snowflake
-- =============================================================================
-- TODO: Create a place inside Snowflake to upload the three files to (no AWS
--       account needed), and upload them from Snowsight.
-- TODO: Describe how to read each file type, once, so you can reuse it.
-- TODO: Load Seller A's CSV into seller_a_orders:
--       order_id INT, customer_name STRING, country STRING,
--       order_ts TIMESTAMP_NTZ, status STRING, amount NUMBER(10,2)
-- TODO: Load Seller B's JSON, then pull it out into seller_b_orders:
--       order_id, customer_name, country, amount
--       (the customer name and country sit inside a nested customer object)
-- Hint: stages, file formats and COPY INTO, Section 5. JSON with dot
--       notation, Section 3.



-- =============================================================================
-- TASK 2: Load Seller C's files automatically as they arrive
-- =============================================================================
-- TODO: Create seller_c_orders:
--       order_id INT, customer_name STRING, country STRING, amount NUMBER(10,2)
-- TODO: Load Seller C's Parquet without a hand-run COPY each time. Only Seller C
--       Parquet files should be picked up, and columns should map by name.
-- TODO: On an internal stage there are no S3 events, so trigger it yourself.
--       Then prove what loaded and when.
-- Hint: Snowpipe, Section 5.



-- =============================================================================
-- TASK 3: Combine every order and send finance a settlement file
-- =============================================================================
-- TODO: Build one table named orders with every order from all three sellers,
--       using exactly these columns, in this order:
--       order_id, customer_name, country, amount, seller
--       (seller is SELLER_A, SELLER_B or SELLER_C)
-- TODO: Show the order count and total amount per seller.
-- TODO: Write orders out as a compressed CSV file with a header row, ready for
--       finance to download.
-- Hint: unloading data, Section 5.



-- =============================================================================
-- TASK 4: Track every change to the orders as it happens
-- =============================================================================
-- TODO: Start capturing every insert, update and delete on orders.
-- Hint: streams and change data capture, Section 6.


-- NEW DAY'S ACTIVITY (given). Run this AFTER your change capture is in place.
-- A late order arrives, one order's amount changes, and one order is removed.
INSERT INTO orders (order_id, customer_name, country, amount, seller)
VALUES (5009, 'Isabella Moore', 'US', 143.75, 'SELLER_A');
UPDATE orders SET amount = 99.00 WHERE order_id = 6001;
DELETE FROM orders WHERE order_id = 7005;

-- TODO: Show the captured changes, and explain how the insert, the update and
--       the delete each appear.



-- =============================================================================
-- TASK 5: Keep payouts and fraud flags up to date on their own
-- =============================================================================
-- The business rules:
--   Seller payout = the sum of amount per seller in orders.
--   Fraud flag    = any new or changed order (not a delete) over 140.
--   Ops digest    = one row per run with the total payout and the number of
--                   flagged orders, built only after both of the above finish.
-- TODO: Record the captured changes into a history table, but only run when
--       there actually are changes.
-- TODO: Rebuild payouts and fraud flags in parallel after that, then build the
--       digest once both are done.
-- TODO: Turn it on, run it now instead of waiting, and check every step ran.
-- Hint: tasks and task graphs, Section 6.



-- =============================================================================
-- TASK 6: Build the payouts a second way, and pick the one you'd use
-- =============================================================================
-- TODO: Build the same seller payouts declaratively, with no stream and no
--       task, kept no more than a minute stale.
-- Hint: dynamic tables, Section 6.


-- ANOTHER ORDER (given). Run this once both payout builds exist.
INSERT INTO orders (order_id, customer_name, country, amount, seller)
VALUES (5010, 'Noah Lee', 'US', 58.00, 'SELLER_A');

-- TODO: Bring both builds up to date, then show the two payouts side by side
--       and confirm they match for every seller.
-- TODO: In a comment, say which approach you would use here and why.



-- =============================================================================
-- Cleanup (optional, run this when you are done to remove what the lab created).
-- Suspend any tasks you resumed before dropping the database.
-- =============================================================================
-- DROP DATABASE IF EXISTS FERNRIDGE;
-- DROP WAREHOUSE IF EXISTS FERNRIDGE_WH;
