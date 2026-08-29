# =============================================================================
# feature-engineering.py  -  runs INSIDE Snowflake, in a Snowflake Notebook
# Section 7: Snowpark, Data Engineering in Python
#
# WHERE THIS RUNS: this is a Snowflake Notebook cell, not a local script. In
# Snowsight open Notebooks, create a notebook on database DELIVERY_ML_LAB, schema
# PUBLIC, warehouse SNOWPARK_ML_WH, add the packages snowflake-ml-python, xgboost
# and scikit-learn from the package picker, paste this file into a Python cell,
# and run it. Every line executes on Snowflake compute; nothing runs on your
# laptop and no data leaves the account.
#
# PREREQ: run ml-setup.sql in a worksheet first so ORDERS and ORDER_LOGISTICS
# exist. This cell reads those two tables, engineers the model features with the
# Snowpark DataFrame API, and writes the DELIVERY_FEATURES table for the training
# notebook.
# =============================================================================

from snowflake.snowpark.context import get_active_session
from snowflake.snowpark import Window
from snowflake.snowpark.functions import col, date_part, when, iff, avg, coalesce, lit

# In a Snowflake Notebook the session already exists; we just grab it.
session = get_active_session()

# Read the two source tables and join them on ORDER_ID. Passing the column name
# gives a natural join, keeping a single ORDER_ID column.
orders = session.table("ORDERS")
logistics = session.table("ORDER_LOGISTICS")
df = orders.join(logistics, ["ORDER_ID"], "inner")

# Calendar features from the order timestamp. ORDER_TS is already a timestamp, so
# we read parts straight off it. All of these are known when the order is placed.
df = (
    df.with_column("ORDER_HOUR", date_part("hour", col("ORDER_TS")))
      .with_column("ORDER_DOW", date_part("dayofweek", col("ORDER_TS")))
      .with_column("IS_WEEKEND", iff(date_part("dayofweek", col("ORDER_TS")).isin([0, 6]), 1, 0))
      .with_column("IS_PEAK", iff((col("ORDER_HOUR") >= 17) & (col("ORDER_HOUR") <= 20), 1, 0))
)

# Encode the priority text as a number, ordered slowest to fastest service level.
df = df.with_column(
    "PRIORITY_CODE",
    when(col("PRIORITY") == "STANDARD", 0).when(col("PRIORITY") == "EXPRESS", 1).otherwise(2),
)

# The key feature, built with a window function. Some couriers run consistently
# late, but the model cannot use the courier name directly. So we give it the
# courier's own track record: the average delay across that courier's PRIOR
# orders, in time order. The frame ends one row before the current order, so a
# row never sees its own delay. That is what keeps this feature leak-free.
prior_by_courier = (
    Window.partition_by("COURIER").order_by("ORDER_TS")
          .rows_between(Window.UNBOUNDED_PRECEDING, -1)
)
df = df.with_column(
    "COURIER_PRIOR_DELAY_AVG", avg(col("DELIVERY_DELAY_MINUTES")).over(prior_by_courier)
)
# A courier's first order has no history, so fill those with the overall average.
global_avg = df.select(avg(col("DELIVERY_DELAY_MINUTES"))).collect()[0][0]
df = df.with_column(
    "COURIER_PRIOR_DELAY_AVG", coalesce(col("COURIER_PRIOR_DELAY_AVG"), lit(global_avg))
)

FEATURES = [
    "DISTANCE_KM", "PACKAGE_WEIGHT_KG", "PRIORITY_CODE", "HANDOFFS", "PRIOR_DELAYS",
    "ORDER_HOUR", "ORDER_DOW", "IS_WEEKEND", "IS_PEAK", "COURIER_PRIOR_DELAY_AVG",
]
LABEL = "DELIVERY_DELAY_MINUTES"

# Save the engineered features. We keep ORDER_TS so the training notebook can
# split the data by time. This table is the hand-off to ml-train.py.
features_df = df.select(["ORDER_ID", "ORDER_TS"] + FEATURES + [LABEL])
features_df.write.mode("overwrite").save_as_table("DELIVERY_FEATURES")
print("DELIVERY_FEATURES rows:", session.table("DELIVERY_FEATURES").count())
