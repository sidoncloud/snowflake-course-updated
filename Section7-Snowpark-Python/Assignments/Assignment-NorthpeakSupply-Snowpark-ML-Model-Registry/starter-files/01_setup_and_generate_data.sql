-- =============================================================================
-- 01_setup_and_generate_data.sql
-- Northpeak Supply: predicting late invoice payments with Snowpark ML
--
-- WHERE TO RUN THIS: a Snowsight SQL worksheet, as ACCOUNTADMIN, once.
-- It creates the lab's own warehouse and database, then generates the three
-- source tables the notebook reads. No file upload is needed.
--   CUSTOMERS  600 business customers (segment, payment terms, autopay ...)
--   INVOICES   9,000 invoices issued from 2025-01-01 to 2026-06-29
--   PAYMENTS   one row per invoice: when it was actually paid
--
-- Every random value uses UNIFORM or NORMAL with its own RANDOM(seed), so the
-- data is identical on every run and in every account.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- 1. The lab's own warehouse, database and schema.
CREATE WAREHOUSE IF NOT EXISTS NORTHPEAK_ML_WH
    WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE
    COMMENT = 'Northpeak Supply late-payment ML lab';
CREATE DATABASE IF NOT EXISTS NORTHPEAK_ML;
CREATE SCHEMA   IF NOT EXISTS NORTHPEAK_ML.CREDIT;
USE WAREHOUSE NORTHPEAK_ML_WH;
USE SCHEMA NORTHPEAK_ML.CREDIT;

-- 2. Customers. DISCIPLINE is a hidden trait (how reliably the customer pays).
--    It drives lateness but is never published: the model has to infer it from
--    the customer's payment history, exactly as a real credit team would.
CREATE OR REPLACE TABLE gen_customers AS
WITH r AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ8())   AS n,
        UNIFORM(1, 100, RANDOM(101))          AS segment_roll,
        UNIFORM(1, 4, RANDOM(102))            AS region_roll,
        UNIFORM(1, 100, RANDOM(103))          AS terms_roll,
        UNIFORM(5, 100, RANDOM(104)) * 1000   AS credit_limit,
        UNIFORM(0, 3286, RANDOM(105))         AS since_offset_days,
        UNIFORM(1, 100, RANDOM(106))          AS autopay_roll,
        NORMAL(0, 1, RANDOM(107))             AS discipline
    FROM TABLE(GENERATOR(ROWCOUNT => 600))
)
SELECT
    'C' || LPAD(n, 4, '0') AS customer_id,
    CASE WHEN segment_roll <= 30 THEN 'RETAIL'
         WHEN segment_roll <= 55 THEN 'HOSPITALITY'
         WHEN segment_roll <= 75 THEN 'CONSTRUCTION'
         WHEN segment_roll <= 90 THEN 'HEALTHCARE'
         ELSE 'EDUCATION' END                                   AS segment,
    CASE region_roll WHEN 1 THEN 'NORTH' WHEN 2 THEN 'SOUTH'
                     WHEN 3 THEN 'EAST' ELSE 'WEST' END          AS region,
    CASE WHEN terms_roll <= 15 THEN 15
         WHEN terms_roll <= 60 THEN 30
         WHEN terms_roll <= 85 THEN 45
         ELSE 60 END                                            AS payment_terms_days,
    credit_limit,
    DATEADD(day, since_offset_days, '2015-01-01'::DATE)         AS customer_since,
    IFF(autopay_roll <= 20, 1, 0)                               AS on_autopay,
    discipline
FROM r;

-- 3. Invoices, plus the true payment outcome. The chance of paying late is a
--    logistic function of real drivers (hidden discipline, segment, terms,
--    autopay, invoice size, early-pay discount, channel, December, tenure).
--    The final draw against LATE_ROLL adds the randomness real life has.
--    Invoices still unpaid 60 days after the due date go to a collection
--    agency, so DAYS_LATE is capped at 60.
CREATE OR REPLACE TABLE gen_invoices AS
WITH r AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ8())        AS n,
        UNIFORM(1, 600, RANDOM(201))               AS customer_n,
        UNIFORM(0, 544, RANDOM(202))               AS day_offset,
        NORMAL(7.4, 0.9, RANDOM(203))              AS log_amount,
        UNIFORM(1, 25, RANDOM(204))                AS line_items,
        UNIFORM(1, 100, RANDOM(205))               AS channel_roll,
        UNIFORM(1, 100, RANDOM(206))               AS discount_roll,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM(207))   AS late_roll,
        UNIFORM(0.001::FLOAT, 1::FLOAT, RANDOM(208)) AS late_size_roll,
        UNIFORM(0, 10, RANDOM(209))                AS early_days,
        UNIFORM(1, 100, RANDOM(210))               AS reminder_roll
    FROM TABLE(GENERATOR(ROWCOUNT => 9000))
),
inv AS (
    SELECT
        r.*,
        c.customer_id, c.segment, c.payment_terms_days, c.on_autopay,
        c.customer_since, c.discipline,
        DATEADD(day, r.day_offset, '2025-01-01'::DATE)          AS invoice_date,
        ROUND(LEAST(GREATEST(EXP(r.log_amount), 50), 60000), 2)  AS amount,
        CASE WHEN r.channel_roll <= 35 THEN 'EDI'
             WHEN r.channel_roll <= 80 THEN 'EMAIL'
             ELSE 'PORTAL' END                                   AS channel,
        IFF(r.discount_roll <= 25, 1, 0)                         AS early_pay_discount
    FROM r
    JOIN gen_customers c ON c.customer_id = 'C' || LPAD(r.customer_n, 4, '0')
),
scored AS (
    SELECT
        inv.*,
        -1.1
        + 1.0 * discipline
        + CASE segment WHEN 'CONSTRUCTION' THEN 1.4 WHEN 'EDUCATION' THEN 1.0
                       WHEN 'HOSPITALITY' THEN 0.7 WHEN 'HEALTHCARE' THEN -0.6 ELSE 0 END
        + CASE payment_terms_days WHEN 15 THEN -0.4 WHEN 45 THEN 0.6 WHEN 60 THEN 1.1 ELSE 0 END
        - 2.6 * on_autopay
        + 1.2 * (LN(amount) - 7.4)
        - 1.3 * early_pay_discount
        + CASE channel WHEN 'PORTAL' THEN -0.8 WHEN 'EDI' THEN -0.4 ELSE 0 END
        + IFF(MONTH(invoice_date) = 12, 1.1, 0)
        + 0.04 * (line_items - 13)
        - 0.06 * DATEDIFF(day, customer_since, invoice_date) / 365.25   AS late_logit
    FROM inv
)
SELECT
    'INV' || LPAD(n, 6, '0')                                       AS invoice_id,
    customer_id, invoice_date,
    DATEADD(day, payment_terms_days, invoice_date)                 AS due_date,
    amount, line_items, channel, early_pay_discount, discipline, reminder_roll,
    IFF(late_roll < 1 / (1 + EXP(-late_logit)), 1, 0)              AS paid_late,
    IFF(late_roll < 1 / (1 + EXP(-late_logit)),
        LEAST(60, 1 + FLOOR(-LN(late_size_roll) * (8 + 6 * GREATEST(discipline, 0)))),
        -early_days)                                               AS days_late
FROM scored;

-- 4. The three tables the lab reads. DISCIPLINE stays behind in the scratch
--    tables, which are dropped at the end of this script.
CREATE OR REPLACE TABLE CUSTOMERS AS
SELECT customer_id, segment, region, payment_terms_days, credit_limit,
       customer_since, on_autopay
FROM gen_customers;

CREATE OR REPLACE TABLE INVOICES AS
SELECT invoice_id, customer_id, invoice_date, due_date, amount, line_items,
       channel, early_pay_discount
FROM gen_invoices;

-- PAYMENTS is what happened AFTER the invoice was issued. REMINDERS_SENT is the
-- number of payment reminders the collections team sent for the invoice.
CREATE OR REPLACE TABLE PAYMENTS AS
SELECT
    invoice_id,
    DATEADD(day, days_late, due_date)                  AS paid_date,
    days_late::INT                                     AS days_late,
    CASE WHEN paid_late = 1 THEN 1 + FLOOR(days_late / 14)
         WHEN reminder_roll <= 15 THEN 1
         ELSE 0 END::INT                               AS reminders_sent
FROM gen_invoices;

-- 5. Drop the scratch tables.
DROP TABLE IF EXISTS gen_customers;
DROP TABLE IF EXISTS gen_invoices;

-- 6. Check the data.
SELECT
    (SELECT COUNT(*) FROM CUSTOMERS) AS customers,
    (SELECT COUNT(*) FROM INVOICES)  AS invoices,
    (SELECT COUNT(*) FROM PAYMENTS)  AS payments;

SELECT
    COUNT(*)                                        AS invoices,
    SUM(IFF(p.days_late > 0, 1, 0))                 AS paid_late,
    ROUND(AVG(IFF(p.days_late > 0, 1, 0)) * 100, 1) AS pct_paid_late,
    MIN(i.invoice_date)                             AS first_invoice,
    MAX(i.invoice_date)                             AS last_invoice
FROM INVOICES i JOIN PAYMENTS p USING (invoice_id);

SELECT i.invoice_id, i.customer_id, i.invoice_date, i.due_date, i.amount,
       p.paid_date, p.days_late
FROM INVOICES i JOIN PAYMENTS p USING (invoice_id)
ORDER BY i.invoice_id
LIMIT 5;
