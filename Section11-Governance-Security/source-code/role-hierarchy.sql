-- =============================================================================
-- LAB - Build a Role Hierarchy and Grant Model
-- Section 11: Governance, Security & Orchestration
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS GOVERNANCE_LAB;
CREATE SCHEMA   IF NOT EXISTS GOVERNANCE_LAB.GOVERNANCE;
USE SCHEMA GOVERNANCE_LAB.GOVERNANCE;

-- 1. Two objects for our roles to act on.
CREATE OR REPLACE TABLE customers (
    customer_id INT, name STRING, email STRING, region STRING);
INSERT INTO customers VALUES
    (1,'Ava','ava@shop.com','EAST'),
    (2,'Liam','liam@shop.com','WEST'),
    (3,'Mia','mia@shop.com','EAST');

CREATE OR REPLACE TABLE orders (
    order_id INT, customer_id INT, amount NUMBER(10,2), status STRING);
INSERT INTO orders VALUES
    (1,1,100,'NEW'),(2,2,200,'SHIPPED'),(3,3,300,'NEW');

-- 2. Create three functional roles: read-only, read-write, and schema owner.
CREATE OR REPLACE ROLE DATA_ANALYST;
CREATE OR REPLACE ROLE DATA_ENGINEER;
CREATE OR REPLACE ROLE DATA_ADMIN;

-- 3. Build the hierarchy. A role granted to another role is inherited by it,
--    so privileges roll upward: analyst -> engineer -> admin.
GRANT ROLE DATA_ANALYST  TO ROLE DATA_ENGINEER;
GRANT ROLE DATA_ENGINEER TO ROLE DATA_ADMIN;
-- By convention the top of a custom hierarchy rolls up to SYSADMIN.
GRANT ROLE DATA_ADMIN    TO ROLE SYSADMIN;

-- 4. Grant privileges at each tier. Grant only the delta a tier adds; the rest
--    is inherited from the role below it.
--    analyst: read-only.
GRANT USAGE ON WAREHOUSE COURSE_WH               TO ROLE DATA_ANALYST;
GRANT USAGE ON DATABASE GOVERNANCE_LAB           TO ROLE DATA_ANALYST;
GRANT USAGE ON SCHEMA GOVERNANCE_LAB.GOVERNANCE  TO ROLE DATA_ANALYST;
GRANT SELECT ON ALL TABLES    IN SCHEMA GOVERNANCE_LAB.GOVERNANCE TO ROLE DATA_ANALYST;
-- FUTURE grants cover tables that do not exist yet, so new tables are auto-readable.
GRANT SELECT ON FUTURE TABLES IN SCHEMA GOVERNANCE_LAB.GOVERNANCE TO ROLE DATA_ANALYST;

--    engineer: adds write and the right to create tables.
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA GOVERNANCE_LAB.GOVERNANCE TO ROLE DATA_ENGINEER;
GRANT CREATE TABLE ON SCHEMA GOVERNANCE_LAB.GOVERNANCE TO ROLE DATA_ENGINEER;

--    admin: full control of the schema.
GRANT ALL ON SCHEMA GOVERNANCE_LAB.GOVERNANCE TO ROLE DATA_ADMIN;

-- 5. Inspect the grant model. Read every row: privilege, granted-on, name.
SHOW GRANTS TO ROLE DATA_ANALYST;
SHOW GRANTS TO ROLE DATA_ENGINEER;   -- note USAGE on ROLE DATA_ANALYST: the inheritance link
SHOW GRANTS TO ROLE DATA_ADMIN;

-- 6. Validate the model live. First disable secondary roles, so the ACTIVE role
--    is the only authority. Without this, Snowflake activates every role you hold
--    and the restriction below would not actually restrict.
USE ROLE DATA_ANALYST;
USE SECONDARY ROLES NONE;
USE WAREHOUSE COURSE_WH;
USE SCHEMA GOVERNANCE_LAB.GOVERNANCE;
SELECT CURRENT_ROLE(), CURRENT_SECONDARY_ROLES();   -- DATA_ANALYST, none

SELECT COUNT(*) FROM customers;                      -- works: analyst can read
INSERT INTO orders VALUES (9,1,999,'NEW');           -- FAILS: analyst has no INSERT
CREATE TABLE nope (id INT);                          -- FAILS: analyst cannot create

-- 7. Engineer inherits the analyst's read, and adds write.
USE ROLE DATA_ENGINEER;
USE SCHEMA GOVERNANCE_LAB.GOVERNANCE;
SELECT COUNT(*) FROM customers;                      -- works: inherited from analyst
INSERT INTO orders VALUES (9,1,999,'NEW');           -- works: engineer can write
DROP TABLE customers;                                -- FAILS: no ownership on the table

-- 8. Admin owns the schema and can do the structural work.
USE ROLE DATA_ADMIN;
USE SCHEMA GOVERNANCE_LAB.GOVERNANCE;
CREATE OR REPLACE TABLE admin_probe (id INT);        -- works
DROP TABLE admin_probe;                              -- works

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- USE ROLE ACCOUNTADMIN;
-- USE SECONDARY ROLES ALL;
-- DROP ROLE IF EXISTS DATA_ADMIN;
-- DROP ROLE IF EXISTS DATA_ENGINEER;
-- DROP ROLE IF EXISTS DATA_ANALYST;
-- DROP TABLE IF EXISTS GOVERNANCE_LAB.GOVERNANCE.customers;
-- DROP TABLE IF EXISTS GOVERNANCE_LAB.GOVERNANCE.orders;
