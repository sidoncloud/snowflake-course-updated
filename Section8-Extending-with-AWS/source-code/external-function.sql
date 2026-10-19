-- =============================================================================
-- LAB - External Functions: calling AWS Lambda from Snowflake
-- Section 8: Extending Snowflake with AWS Services
--
-- Files in this folder:
--   lambda_function.py           the Lambda code (order-tax)
--   ext-func-invoke-policy.json  inline policy that lets the IAM role call the API
--   ext-func-trust-policy.json   trust policy that lets Snowflake assume the role
--   external-function.sql        this file, the Snowsight part
--
-- Do everything in AWS region us-east-1 (N. Virginia).
-- Replace <your-account-id> and <your-api-id> with your own values.
--
-- ORDER OF STEPS
--   AWS console
--     1. Lambda: create function order-tax, Python 3.12, paste lambda_function.py, Deploy.
--     2. API Gateway: create REST API snowflake-ext-func-api (Regional).
--        Create resource snowflake, then a POST method on it:
--        integration type Lambda function, Lambda proxy integration ON, function order-tax.
--     3. API Gateway: on the POST method, Method request > Edit > Authorization = AWS IAM.
--     4. API Gateway: Deploy API to a new stage named prod.
--        Copy the Invoke URL of POST /snowflake. It looks like
--        https://<your-api-id>.execute-api.us-east-1.amazonaws.com/prod/snowflake
--     5. IAM: create role snowflake-ext-func-api-role, trusted entity = AWS account,
--        This account (a placeholder, replaced in step 8).
--     6. IAM: on that role, Add permissions > Create inline policy > JSON,
--        paste ext-func-invoke-policy.json, fill in your account id and API id.
--        Copy the role ARN.
--   Snowsight
--     7. Run STEP 7 below (API integration), then DESC INTEGRATION and copy
--        API_AWS_IAM_USER_ARN and API_AWS_EXTERNAL_ID.
--   AWS console
--     8. IAM: on the role, Trust relationships > Edit trust policy,
--        paste ext-func-trust-policy.json with the two values from step 7.
--   Snowsight
--     9. Run STEP 9 onward below (create the external function and call it).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

CREATE DATABASE IF NOT EXISTS EXTFUNC_LAB;
CREATE SCHEMA   IF NOT EXISTS EXTFUNC_LAB.EXT;
USE SCHEMA EXTFUNC_LAB.EXT;

-- STEP 7. Create the API integration. Paste your role ARN and Invoke URL.
CREATE OR REPLACE API INTEGRATION order_tax_api_int
  API_PROVIDER = aws_api_gateway
  API_AWS_ROLE_ARN = 'arn:aws:iam::<your-account-id>:role/snowflake-ext-func-api-role'
  API_ALLOWED_PREFIXES = ('https://<your-api-id>.execute-api.us-east-1.amazonaws.com/prod/snowflake')
  ENABLED = TRUE;

-- Copy API_AWS_IAM_USER_ARN and API_AWS_EXTERNAL_ID from the output.
DESC INTEGRATION order_tax_api_int;

-- Now go back to AWS and do step 8 (the trust policy) before continuing.
-- If you skip it, every call below fails with a 403.

-- STEP 9. Create the external function. The AS clause is your Invoke URL.
CREATE OR REPLACE EXTERNAL FUNCTION add_sales_tax(amount FLOAT)
  RETURNS FLOAT
  API_INTEGRATION = order_tax_api_int
  AS 'https://<your-api-id>.execute-api.us-east-1.amazonaws.com/prod/snowflake';

-- STEP 10. Call it on literal values.
SELECT add_sales_tax(100)    AS a,      -- 108
       add_sales_tax(250.50) AS b;      -- 270.54

-- STEP 11. Call it across a table.
CREATE OR REPLACE TABLE orders_raw (order_id INT, product STRING, amount FLOAT);
INSERT INTO orders_raw VALUES
  (1, 'Keyboard', 49.99),
  (2, 'Monitor',  219.00),
  (3, 'Laptop',   1299.00);

SELECT order_id, product, amount, add_sales_tax(amount) AS amount_with_tax
FROM orders_raw
ORDER BY order_id;
-- 49.99 -> 53.99, 219.00 -> 236.52, 1299.00 -> 1402.92

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP FUNCTION IF EXISTS add_sales_tax(FLOAT);
-- DROP TABLE IF EXISTS orders_raw;
-- DROP INTEGRATION IF EXISTS order_tax_api_int;
-- DROP DATABASE IF EXISTS EXTFUNC_LAB;
-- Then in the AWS console delete the snowflake-ext-func-api REST API,
-- the order-tax Lambda function and the snowflake-ext-func-api-role IAM role.
