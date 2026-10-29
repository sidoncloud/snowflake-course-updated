# Northpeak Supply: Late Invoice Payments with Snowpark ML (Starter Kit)

## The scenario

Northpeak Supply is a wholesale distributor, and about a quarter of its invoices get paid after the due date. Today the collections team only finds out when the money doesn't arrive, and the one rule they use is to chase customers who were late before. They want every new invoice scored on the day it's issued, so they can call the riskiest customers before the due date. You build that model entirely inside Snowflake, in a Snowflake Notebook.

## The data you get

Nothing to upload. `01_setup_and_generate_data.sql` generates the data in SQL with fixed random seeds, so everyone gets identical tables.

- `CUSTOMERS` (600 rows): customer_id, segment, region, payment_terms_days, credit_limit, customer_since, on_autopay.
- `INVOICES` (9,000 rows, issued 2025-01-01 to 2026-06-29): invoice_id, customer_id, invoice_date, due_date, amount, line_items, channel, early_pay_discount.
- `PAYMENTS` (one row per invoice): invoice_id, paid_date, days_late (negative means paid early), reminders_sent.

An invoice is late when `days_late > 0`. All names are synthetic.

## Your tasks

1. Explore the data and find what drives late payment
2. Find the column that gives the answer away, and keep it out
3. Build features using only what was known on the invoice date
4. Train a model and test it on invoices it has never seen
5. Prove it beats the rule collections uses today
6. Register the model so it's ready to score new invoices

## Prerequisites

- A Snowflake trial account with the ACCOUNTADMIN role and access to Snowflake Notebooks.
- The notebook packages `snowflake-ml-python`, `xgboost` and `scikit-learn` from the Snowflake Anaconda channel. Accept the Anaconda terms in Snowsight if you are asked to.

## How to start

1. Open a SQL worksheet in Snowsight and run `01_setup_and_generate_data.sql` top to bottom, once. It creates `NORTHPEAK_ML_WH`, the `NORTHPEAK_ML.CREDIT` schema and the three tables.
2. In Snowsight, go to Projects, Notebooks, click the arrow next to + Notebook and choose Import .ipynb file. Import `northpeak_starter.ipynb`, set the location to `NORTHPEAK_ML.CREDIT`, choose Run on warehouse, and pick `NORTHPEAK_ML_WH` as the query warehouse.
3. In the notebook, open Packages and add `snowflake-ml-python`, `xgboost` and `scikit-learn` (the same list as `environment.yml`).
4. Run the setup cell, then fill in one cell per task, in order. Tasks 5 and 6 reuse the variables from Task 4.

## Files

- `01_setup_and_generate_data.sql`: warehouse, database, schema and the generated data. Run it first.
- `northpeak_starter.ipynb`: the notebook skeleton, with one markdown cell and one TODO code cell per task.
- `environment.yml`: the notebook's package list.

Full solution with a step-by-step walkthrough and source code: https://cognifydata.com/labs/snowpark-ml-xgboost-model-registry-late-invoice-payments (free, no sign-up).
