# Lambda handler for the order-tax function.
# Paste this into lambda_function.py in the Lambda code editor, then click Deploy.
#
# Snowflake sends a batch of rows as {"data": [[row_number, amount], ...]}.
# The function adds 8% sales tax to each amount and returns
# {"data": [[row_number, taxed_amount], ...]} with one entry per input row.

import json


def lambda_handler(event, context):
    # With Lambda proxy integration, API Gateway passes the body as a string.
    body = json.loads(event["body"])
    rows = body["data"]

    out = []
    for row in rows:
        row_number = row[0]
        amount = row[1]
        taxed = round(float(amount) * 1.08, 2)
        out.append([row_number, taxed])

    return {"statusCode": 200, "body": json.dumps({"data": out})}
