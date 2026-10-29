# Fernridge Market: Multi-Format Ingestion and Pipelines Assignment (Starter Kit)

## The scenario

Fernridge Market is an online marketplace, and three sellers send it their daily orders, each in a different file format. Seller C sends files all day, so loading them by hand doesn't scale. Finance needs one combined view of every order and a settlement file it can download, and the operations team needs seller payouts and fraud flags that keep themselves up to date as orders change.

## The data you get

Three small order files in `dataset/`:

- `sellerA_orders.csv`: 8 orders (5001 to 5008) with a header row. Columns: order_id, customer_name, country, order_ts, status, amount.
- `sellerB_orders.json`: 6 orders (6001 to 6006), newline-delimited JSON. The customer's name and country sit inside a nested `customer` object.
- `sellerC_orders.parquet`: 5 orders (7001 to 7005). Columns: order_id, customer_name, country, amount.

`starter.sql` also gives you the "new day's activity" (one insert, one update, one delete) for Task 4 and one extra order for Task 6. All names are synthetic.

## Your tasks

1. Load all three sellers' files into Snowflake
2. Load Seller C's files automatically as they arrive
3. Combine every order and send finance a settlement file
4. Track every change to the orders as it happens
5. Keep payouts and fraud flags up to date on their own
6. Build the payouts a second way, and pick the one you'd use

## Prerequisites

- A Snowflake trial account with the ACCOUNTADMIN role. No AWS account is needed: you load the files through a stage inside Snowflake.

## How to start

1. Open a new SQL worksheet in Snowsight and paste in `starter.sql`.
2. Run the SETUP block. It creates `FERNRIDGE_WH` and the `FERNRIDGE.MARKET` schema.
3. Start Task 1. Once your stage exists, upload the three files from `dataset/` in Snowsight (open the stage under Data, Databases, FERNRIDGE, MARKET, Stages, then click + Files).
4. Use the exact table and column names the TODO comments give you, because the given INSERT, UPDATE and DELETE statements in Tasks 4 and 6 depend on them.

## Files

- `starter.sql`: setup, the given change statements, and one TODO section per task.
- `dataset/`: the three seller files.

Full solution with a step-by-step walkthrough and source code: https://cognifydata.com/labs/snowflake-multi-format-ingestion-pipeline-orchestration (free, no sign-up).
