# =============================================================================
# ml-serve.py  -  runs INSIDE Snowflake, in a Snowflake Notebook
# Section 7: Snowpark, Data Engineering in Python
#
# WHERE THIS RUNS: this is a Snowflake Notebook cell, not a local script. Use the
# same notebook setup as the other two files (database DELIVERY_ML_LAB, schema
# PUBLIC, warehouse SNOWPARK_ML_WH, packages snowflake-ml-python, xgboost,
# scikit-learn). Paste this into a Python cell and run it. Loading, scoring and
# training all happen on Snowflake compute.
#
# PREREQ: run feature-engineering.py then ml-train.py first, so DELIVERY_FEATURES,
# DELIVERY_NEW_ORDERS and the registered V1 model all exist. This cell loads V1
# (without retraining it), batch-scores the new orders, then trains a candidate
# V2, registers it, and promotes whichever version wins on error.
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

# Load the V1 model the training notebook registered. We do not rebuild it; we
# pull the exact versioned artifact out of the registry.
reg = Registry(session=session, database_name=DATABASE, schema_name=SCHEMA)
model = reg.get_model(MODEL_NAME)
v1 = model.version("V1")
print(reg.show_models()[["name", "versions", "default_version_name"]].to_string())
print("V1 metrics:", v1.show_metrics())

# Batch inference with V1 on the new orders. run scores the rows on the warehouse,
# next to the data. It keeps the input columns and adds a prediction column, which
# we rename and keep next to ORDER_ID.
new_orders = session.table("DELIVERY_NEW_ORDERS")
scored = v1.run(new_orders, function_name="predict")
pred_col = [c for c in scored.columns if c not in new_orders.columns][0]
predictions = scored.select(
    "ORDER_ID", col(pred_col).cast("number(10,2)").alias("PREDICTED_DELAY")
)
predictions.write.mode("overwrite").save_as_table("DELIVERY_PREDICTIONS")
print("DELIVERY_PREDICTIONS rows:", session.table("DELIVERY_PREDICTIONS").count())
predictions.order_by("ORDER_ID").show(5)

# The improvement loop. Read the features back and split on time exactly as the
# training notebook did, so V1 and V2 are judged on the identical holdout.
features = (session.table("DELIVERY_FEATURES")
            .with_column("ORDER_EPOCH", date_part("epoch_second", col("ORDER_TS"))))
cutoff = features.stat.approx_quantile("ORDER_EPOCH", [0.8])[0]
train_pd = features.filter(col("ORDER_EPOCH") <= lit(cutoff)).select(FEATURES + [LABEL]).to_pandas()
test_pd = features.filter(col("ORDER_EPOCH") > lit(cutoff)).select(FEATURES + [LABEL]).to_pandas()

# Train a candidate V2, deeper and with more trees. Whether it actually wins is an
# empirical question we answer with the metric, not a promise.
model_v2 = xgb.XGBRegressor(max_depth=8, n_estimators=400, random_state=42)
model_v2.fit(train_pd[FEATURES], train_pd[LABEL])
mae_v2 = float(mean_absolute_error(test_pd[LABEL], model_v2.predict(test_pd[FEATURES])))
r2_v2 = float(r2_score(test_pd[LABEL], model_v2.predict(test_pd[FEATURES])))
print(f"V2 candidate. MAE: {mae_v2:.2f} minutes, R2: {r2_v2:.3f}")

if "V2" in [v.version_name for v in model.versions()]:
    model.delete_version("V2")
reg.log_model(
    model_v2, model_name=MODEL_NAME, version_name="V2",
    comment="XGBoost regressor, deeper and more estimators",
    metrics={"mean_absolute_error": mae_v2, "r2_score": r2_v2},
    sample_input_data=train_pd[FEATURES].head(100),
)

# Promote by metric. Lower error wins, and we set the registry default to it, so
# every future call serves the best version without anyone changing their code.
mae_v1 = float(v1.show_metrics()["mean_absolute_error"])
best = "V2" if mae_v2 < mae_v1 else "V1"
model.default = best
print(f"V1 MAE {mae_v1:.2f} vs V2 MAE {mae_v2:.2f}. Default is now {model.default.version_name}.")
print(reg.show_models()[["name", "versions", "default_version_name"]].to_string())
