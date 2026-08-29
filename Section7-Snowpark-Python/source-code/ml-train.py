# =============================================================================
# ml-train.py  -  runs INSIDE Snowflake, in a Snowflake Notebook
# Section 7: Snowpark, Data Engineering in Python
#
# WHERE THIS RUNS: this is a Snowflake Notebook cell, not a local script. Use the
# same notebook you ran feature-engineering.py in (database DELIVERY_ML_LAB,
# schema PUBLIC, warehouse SNOWPARK_ML_WH, with the packages snowflake-ml-python,
# xgboost and scikit-learn added). Paste this into a new Python cell and run it.
# Training runs on Snowflake compute; nothing trains on your laptop.
#
# PREREQ: run feature-engineering.py first so DELIVERY_FEATURES exists. This cell
# splits that table by time, trains an XGBoost regressor, evaluates it, registers
# the model to the Model Registry as V1, and saves a batch of new orders to score.
# =============================================================================

from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.functions import col, date_part, lit
import xgboost as xgb
from sklearn.metrics import mean_absolute_error, r2_score
from snowflake.ml.registry import Registry

session = get_active_session()

DATABASE = "DELIVERY_ML_LAB"
SCHEMA = "PUBLIC"
MODEL_NAME = "DELIVERY_DELAY_MODEL"
FEATURES = [
    "DISTANCE_KM", "PACKAGE_WEIGHT_KG", "PRIORITY_CODE", "HANDOFFS", "PRIOR_DELAYS",
    "ORDER_HOUR", "ORDER_DOW", "IS_WEEKEND", "IS_PEAK", "COURIER_PRIOR_DELAY_AVG",
]
LABEL = "DELIVERY_DELAY_MINUTES"

# Split by TIME, not at random. We train on the earlier 80% of orders and test on
# the most recent 20%, because in production you predict the future from the past.
# A random split would let tomorrow's orders leak into training.
features = (session.table("DELIVERY_FEATURES")
            .with_column("ORDER_EPOCH", date_part("epoch_second", col("ORDER_TS"))))
cutoff = features.stat.approx_quantile("ORDER_EPOCH", [0.8])[0]
train_sdf = features.filter(col("ORDER_EPOCH") <= lit(cutoff))
test_sdf = features.filter(col("ORDER_EPOCH") > lit(cutoff))

# Materialize the two splits inside the notebook's Snowflake compute and train the
# XGBoost model there. This runs in Snowflake, not on a client machine.
train_pd = train_sdf.select(FEATURES + [LABEL]).to_pandas()
test_pd = test_sdf.select(FEATURES + [LABEL]).to_pandas()
print(f"train rows: {len(train_pd)}  test rows: {len(test_pd)}")

model = xgb.XGBRegressor(max_depth=6, n_estimators=200, random_state=42)
model.fit(train_pd[FEATURES], train_pd[LABEL])

# Evaluate on the held-out recent orders the model never saw.
preds = model.predict(test_pd[FEATURES])
mae = float(mean_absolute_error(test_pd[LABEL], preds))
r2 = float(r2_score(test_pd[LABEL], preds))
print(f"Mean Absolute Error: {mae:.2f} minutes")
print(f"R2 score: {r2:.3f}")

# Register the trained model to the Model Registry as V1, with its metrics and an
# input sample. This is the artifact the serving notebook loads. Deleting any
# existing copy first keeps the notebook safe to re-run.
reg = Registry(session=session, database_name=DATABASE, schema_name=SCHEMA)
if MODEL_NAME in [m.name for m in reg.models()]:
    reg.delete_model(MODEL_NAME)
reg.log_model(
    model,
    model_name=MODEL_NAME,
    version_name="V1",
    comment="XGBoost regressor predicting delivery delay in minutes",
    metrics={"mean_absolute_error": mae, "r2_score": r2},
    sample_input_data=train_pd[FEATURES].head(100),
)
print(f"Registered {MODEL_NAME} version V1")

# Save the recent test orders as a scoring batch for the serving notebook: the
# same features, without the label, standing in for freshly dispatched orders.
test_sdf.select(["ORDER_ID"] + FEATURES).write.mode("overwrite").save_as_table("DELIVERY_NEW_ORDERS")
print("DELIVERY_NEW_ORDERS rows:", session.table("DELIVERY_NEW_ORDERS").count())
