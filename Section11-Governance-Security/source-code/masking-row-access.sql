-- =============================================================================
-- LAB - Apply a Masking Policy and a Row Access Policy
-- Section 11: Governance, Security & Orchestration
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS GOVERNANCE_LAB;
CREATE SCHEMA   IF NOT EXISTS GOVERNANCE_LAB.GOVERNANCE;
USE SCHEMA GOVERNANCE_LAB.GOVERNANCE;

-- 1. A table with PII (email, phone) and a region column to filter rows on.
CREATE OR REPLACE TABLE customers_pii (
    customer_id INT, name STRING, email STRING, phone STRING, region STRING);
INSERT INTO customers_pii VALUES
    (1,'Ava','ava@shop.com','555-1000','EAST'),
    (2,'Liam','liam@shop.com','555-2000','WEST'),
    (3,'Mia','mia@shop.com','555-3000','EAST'),
    (4,'Noah','noah@shop.com','555-4000','WEST');

-- 2. Two roles: one privileged (sees everything), one restricted (support desk).
CREATE OR REPLACE ROLE PII_ADMIN;
CREATE OR REPLACE ROLE SUPPORT;
GRANT ROLE PII_ADMIN TO ROLE SYSADMIN;
GRANT ROLE SUPPORT   TO ROLE SYSADMIN;
GRANT USAGE ON WAREHOUSE COURSE_WH TO ROLE PII_ADMIN;
GRANT USAGE ON WAREHOUSE COURSE_WH TO ROLE SUPPORT;
GRANT USAGE ON DATABASE GOVERNANCE_LAB          TO ROLE PII_ADMIN;
GRANT USAGE ON DATABASE GOVERNANCE_LAB          TO ROLE SUPPORT;
GRANT USAGE ON SCHEMA GOVERNANCE_LAB.GOVERNANCE TO ROLE PII_ADMIN;
GRANT USAGE ON SCHEMA GOVERNANCE_LAB.GOVERNANCE TO ROLE SUPPORT;
GRANT SELECT ON TABLE customers_pii TO ROLE PII_ADMIN;
GRANT SELECT ON TABLE customers_pii TO ROLE SUPPORT;

-- 3. A masking policy for the email column. It runs at query time and decides
--    what each session sees based on its active role. The stored data is untouched.
CREATE OR REPLACE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN','PII_ADMIN') THEN val
        ELSE REGEXP_REPLACE(val, '.+@', '****@')
    END;
ALTER TABLE customers_pii MODIFY COLUMN email SET MASKING POLICY email_mask;

-- 4. A row access policy on region. It returns TRUE to keep a row, FALSE to hide it.
CREATE OR REPLACE ROW ACCESS POLICY region_policy AS (region STRING) RETURNS BOOLEAN ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN','PII_ADMIN') THEN TRUE
        WHEN CURRENT_ROLE() = 'SUPPORT' AND region = 'EAST'  THEN TRUE
        ELSE FALSE
    END;
ALTER TABLE customers_pii ADD ROW ACCESS POLICY region_policy ON (region);

-- 5. Tag-based masking: the scalable pattern. Attach a policy to a TAG once, then
--    any column you tag inherits that policy automatically.
CREATE OR REPLACE TAG pii_class;
CREATE OR REPLACE MASKING POLICY phone_mask AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN','PII_ADMIN') THEN val
        ELSE '***-****'
    END;
ALTER TAG pii_class SET MASKING POLICY phone_mask;
ALTER TABLE customers_pii MODIFY COLUMN phone SET TAG pii_class = 'PHONE';

-- 6. See it as ACCOUNTADMIN: exempt role, all rows, real email and phone.
SELECT customer_id, email, phone, region FROM customers_pii ORDER BY customer_id;

-- 7. See it as SUPPORT: email and phone masked, and only EAST rows survive.
--    Disable secondary roles first so SUPPORT is the sole active role.
USE ROLE SUPPORT;
USE SECONDARY ROLES NONE;
USE WAREHOUSE COURSE_WH;
USE SCHEMA GOVERNANCE_LAB.GOVERNANCE;
SELECT customer_id, email, phone, region FROM customers_pii ORDER BY customer_id;
SELECT COUNT(*) FROM customers_pii;    -- 2, not 4: the WEST rows are filtered out

-- 8. Governance visibility: where does the tag live? (immediate, no latency)
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;
SELECT SYSTEM$GET_TAG('pii_class','GOVERNANCE_LAB.GOVERNANCE.customers_pii.phone','COLUMN');

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- USE ROLE ACCOUNTADMIN;
-- DROP TABLE IF EXISTS GOVERNANCE_LAB.GOVERNANCE.customers_pii;   -- detaches its policies
-- ALTER TAG IF EXISTS pii_class UNSET MASKING POLICY;
-- DROP MASKING POLICY IF EXISTS email_mask;
-- DROP MASKING POLICY IF EXISTS phone_mask;
-- DROP ROW ACCESS POLICY IF EXISTS region_policy;
-- DROP TAG IF EXISTS pii_class;
-- DROP ROLE IF EXISTS PII_ADMIN;
-- DROP ROLE IF EXISTS SUPPORT;
