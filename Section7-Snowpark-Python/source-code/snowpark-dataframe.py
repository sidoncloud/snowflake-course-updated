import os

# Read connections.toml from this script's folder instead of the home directory.
os.environ["SNOWFLAKE_HOME"] = os.path.dirname(os.path.abspath(__file__))

from snowflake.snowpark import Session, Window
from snowflake.snowpark.functions import col, sum as sum_, count as count_, rank

# 1. A Session is your connection into Snowflake. The details live in the
#    connections.toml next to this file, so nothing sensitive shows up here.
session = Session.builder.config("connection_name", "snowcourse").create()
session.use_warehouse("COURSE_WH")  # change to your own warehouse name

# 2. Point at the sample TPCH tables. session.table hands back a lazy DataFrame;
#    no data has moved yet.
orders = session.table("SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS")
customers = session.table("SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER")

# 3. filter keeps the rows we want. Here we keep only the high-value orders.
big_orders = orders.filter(col("O_TOTALPRICE") > 400000)

# 4. join brings the two DataFrames together. The keys have different names, so
#    we join on the expression O_CUSTKEY = C_CUSTKEY.
joined = big_orders.join(customers, big_orders["O_CUSTKEY"] == customers["C_CUSTKEY"])

# 5. group_by with agg rolls the orders up to revenue and order count per market
#    segment.
revenue_by_segment = joined.group_by("C_MKTSEGMENT").agg(
    sum_("O_TOTALPRICE").alias("TOTAL_REVENUE"),
    count_("*").alias("ORDER_COUNT"),
)

# 6. The chain is still lazy. Look at the single SQL query Snowpark compiled it
#    into. That is pushdown, from the last lecture, in action.
print("Generated SQL:")
print(revenue_by_segment.queries["queries"][0])

# 7. show is an action, so this is the line that actually runs the query.
revenue_by_segment.show()

# 8. One more transformation: total spend per customer, then a window ranking to
#    number the biggest spenders. rank() over an ordered window does the ranking
#    inside Snowflake.
spend_per_customer = joined.group_by("C_NAME").agg(
    sum_("O_TOTALPRICE").alias("SPEND")
)
ranked = spend_per_customer.with_column(
    "RANK", rank().over(Window.order_by(col("SPEND").desc()))
).sort(col("RANK"))
ranked.show(10)

session.close()
