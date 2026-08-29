# Section 5 - Sample Datasets

Upload these to your own S3 bucket before running the labs.

| File               | Upload to                          | Used by            |
|--------------------|------------------------------------|--------------------|
| orders.csv         | s3://<your-bucket>/raw/csv/         | COPY INTO lab (L27) |
| events.json        | s3://<your-bucket>/raw/json/        | COPY INTO lab (L27) |
| orders.parquet     | s3://<your-bucket>/raw/parquet/     | COPY INTO lab (L27) |
| stream_orders.csv  | s3://<your-bucket>/stream/ (during the lab) | Snowpipe lab (L28) |

Schemas:
- orders.csv - order_id, customer_name, country, order_ts, status, amount (25 rows, with header)
- events.json - newline-delimited JSON, each record has order_id and a nested customer object (12 records)
- orders.parquet - order_id, customer_name, country, amount (18 rows)
- stream_orders.csv - same 6 columns as orders.csv (3 rows), drop it into the stream/ prefix to trigger Snowpipe
