-- =============================================================================
-- LAB - Your first queries in Snowsight
-- Section 1: Introduction & Setup
-- Open a new worksheet in Snowsight and run these one at a time.
-- =============================================================================

-- Which Snowflake version am I on?
SELECT CURRENT_VERSION();

-- Confirm the account is on AWS, in the region I chose at signup.
SELECT CURRENT_ACCOUNT(), CURRENT_REGION();

-- What compute came with the trial? (the warehouse that costs credits when it runs)
SHOW WAREHOUSES;
