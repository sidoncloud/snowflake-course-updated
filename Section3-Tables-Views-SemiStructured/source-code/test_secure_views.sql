-- =============================================================================
-- test_secure_views.sql - Prove a secure view hides its definition
-- Section 3: Tables, Views & Semi-Structured Data
--
-- A secure view lets another role QUERY the data, but not READ the view's logic.
-- Here we create a fresh role, give it access, then try to see the definition.
-- PREREQ: create the views first (SNOWFLAKE_LABS.RETAIL.v_order_summary and
-- v_customer_contact_secure from the views lab).
-- =============================================================================

-- ---- Part 1: setup. Run as ACCOUNTADMIN. ----
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS DEMO_ANALYST;

-- Let the role reach the data: the warehouse, the database, the schema, and
-- SELECT on the two views.
GRANT USAGE ON WAREHOUSE COURSE_WH            TO ROLE DEMO_ANALYST;
GRANT USAGE ON DATABASE  SNOWFLAKE_LABS       TO ROLE DEMO_ANALYST;
GRANT USAGE ON SCHEMA    SNOWFLAKE_LABS.RETAIL TO ROLE DEMO_ANALYST;
GRANT SELECT ON VIEW SNOWFLAKE_LABS.RETAIL.v_order_summary           TO ROLE DEMO_ANALYST;
GRANT SELECT ON VIEW SNOWFLAKE_LABS.RETAIL.v_customer_contact_secure TO ROLE DEMO_ANALYST;

-- Grant the role to yourself so you can switch into it. This works for any user,
-- no need to type your username.
SET _me = CURRENT_USER();
GRANT ROLE DEMO_ANALYST TO USER IDENTIFIER($_me);

-- ---- Part 2: the test. Run these in a DIFFERENT worksheet. ----
USE ROLE DEMO_ANALYST;

-- IMPORTANT: your other roles stay active as "secondary roles", and they would
-- still see you as the owner. Drop them so you are a true non-owner:
USE SECONDARY ROLES NONE;

USE WAREHOUSE COURSE_WH;
USE SCHEMA SNOWFLAKE_LABS.RETAIL;

-- (a) The role CAN query the secure view, no problem:
SELECT * FROM v_customer_contact_secure;

-- (b) But it CANNOT read the secure view's definition. This ERRORS with
--     "Object does not exist, or operation cannot be performed":
SELECT GET_DDL('view', 'v_customer_contact_secure');

-- (c) Compare: a standard view shows its full definition to anyone:
SELECT GET_DDL('view', 'v_order_summary');

-- ---- Reset back to admin. ----
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

-- Cleanup (optional, run this when you are done to remove what this created):
-- DROP ROLE IF EXISTS DEMO_ANALYST;
