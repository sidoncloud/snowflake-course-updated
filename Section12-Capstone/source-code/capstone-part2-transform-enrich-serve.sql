-- =============================================================================
-- CAPSTONE, Part 2: Dynamic Tables, Cortex, and Governed Serving
-- Section 12: End-to-End Pipeline on AWS
-- Flow:  raw_tickets -> tickets_clean (Dynamic Table) -> tickets_enriched
--        (Dynamic Table + Cortex AI functions) -> tickets_service (governed view + masking)
-- Run in a Snowsight worksheet as ACCOUNTADMIN, after Part 1.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
USE SCHEMA CAPSTONE_LAB.CAPSTONE;

-- 1. CLEAN LAYER, as a Dynamic Table.
--    We flatten the VARIANT into typed columns and normalize region. TARGET_LAG
--    DOWNSTREAM means this table refreshes only as fast as what reads from it.
CREATE OR REPLACE DYNAMIC TABLE tickets_clean
  TARGET_LAG = DOWNSTREAM
  WAREHOUSE  = COURSE_WH
AS
SELECT
  raw:ticket_id::int            AS ticket_id,
  raw:customer_name::string     AS customer_name,
  raw:customer_email::string    AS customer_email,
  raw:product::string           AS product,
  UPPER(raw:region::string)     AS region,
  raw:channel::string           AS channel,
  raw:created_at::timestamp_ntz AS created_at,
  raw:message::string           AS message
FROM raw_tickets
WHERE raw:ticket_id IS NOT NULL;

SELECT * FROM tickets_clean ORDER BY ticket_id;

-- 2. ENRICHED LAYER, a Dynamic Table that calls Cortex AI functions on the ticket text.
--    AI_AGG answers a prompt over the text it is given. With GROUP BY ALL every
--    ticket is its own group, so each ticket gets its own answer: one for the
--    sentiment and one for the category. AI_SUMMARIZE_AGG writes a short summary.
--    These functions work on trial accounts. We give this table a TARGET_LAG of
--    1 hour so the AI functions are not run more often than needed.
CREATE OR REPLACE DYNAMIC TABLE tickets_enriched
  TARGET_LAG = '1 hour'
  WAREHOUSE  = COURSE_WH
AS
SELECT
  c.*,
  AI_AGG(c.message,
    'Classify the overall sentiment of this support ticket. Answer with exactly one word: Negative, Neutral or Positive.'
  )                                                                 AS sentiment,
  AI_AGG(c.message,
    'Classify this support ticket into exactly one of these categories: Billing, Shipping, Product Defect, Account Access, General. Answer with the category name only.'
  )                                                                 AS category,
  AI_SUMMARIZE_AGG(c.message)                                       AS summary
FROM tickets_clean c
GROUP BY ALL;

SELECT ticket_id, sentiment, category, summary
FROM tickets_enriched
ORDER BY ticket_id;

-- 3. GOVERNANCE, a masking policy on the customer email.
--    Privileged roles see the real address; everyone else sees it masked.
CREATE OR REPLACE MASKING POLICY email_mask AS (val string) RETURNS string ->
  CASE
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN') THEN val
    ELSE REGEXP_REPLACE(val, '^[^@]+', '****')
  END;

-- 4. SERVING LAYER, a governed view.
--    It shapes the enriched rows for consumers and derives a priority from the
--    sentiment: Negative is HIGH, Neutral is MEDIUM, Positive is LOW.
--    The masking policy is applied to the email column of this view.
CREATE OR REPLACE VIEW tickets_service AS
SELECT
  ticket_id,
  customer_name,
  customer_email,
  product,
  region,
  channel,
  created_at,
  category,
  sentiment,
  CASE sentiment
    WHEN 'Negative' THEN 'HIGH'
    WHEN 'Neutral'  THEN 'MEDIUM'
    ELSE 'LOW'
  END AS priority,
  summary
FROM tickets_enriched;

ALTER VIEW tickets_service ALTER COLUMN customer_email SET MASKING POLICY email_mask;

-- 5. A throwaway analyst role to prove the masking works.
CREATE ROLE IF NOT EXISTS capstone_analyst;
GRANT USAGE  ON WAREHOUSE COURSE_WH                        TO ROLE capstone_analyst;
GRANT USAGE  ON DATABASE  CAPSTONE_LAB                   TO ROLE capstone_analyst;
GRANT USAGE  ON SCHEMA    CAPSTONE_LAB.CAPSTONE          TO ROLE capstone_analyst;
GRANT SELECT ON VIEW      CAPSTONE_LAB.CAPSTONE.tickets_service TO ROLE capstone_analyst;
SET capstone_user = CURRENT_USER();
GRANT ROLE capstone_analyst TO USER IDENTIFIER($capstone_user);

-- 6. As ACCOUNTADMIN you see the real email and the full serving row.
SELECT ticket_id, customer_email, category, priority
FROM tickets_service
ORDER BY ticket_id;

-- 7. As the analyst the email comes back masked, everything else is intact.
USE ROLE capstone_analyst;
USE WAREHOUSE COURSE_WH;
SELECT ticket_id, customer_email, category, priority
FROM CAPSTONE_LAB.CAPSTONE.tickets_service
ORDER BY ticket_id;
USE ROLE ACCOUNTADMIN;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP VIEW IF EXISTS tickets_service;
-- DROP DYNAMIC TABLE IF EXISTS tickets_enriched;
-- DROP DYNAMIC TABLE IF EXISTS tickets_clean;
-- DROP MASKING POLICY IF EXISTS email_mask;
-- DROP TABLE IF EXISTS raw_tickets;
-- DROP ROLE IF EXISTS capstone_analyst;
-- DROP STAGE IF EXISTS tickets_stage;
-- DROP FILE FORMAT IF EXISTS ff_json;
-- DROP STORAGE INTEGRATION IF EXISTS capstone_s3_int;
-- Then in AWS: delete the capstone/ folder in the bucket and the snowflake-capstone-role.
