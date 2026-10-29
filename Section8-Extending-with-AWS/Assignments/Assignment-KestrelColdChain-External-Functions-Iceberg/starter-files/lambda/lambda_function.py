# lambda_function.py - Kestrel Cold Chain CO2e calculator (AWS Lambda, Python 3.12)
#
# This is the emissions service the sustainability team owns. Snowflake calls it
# through API Gateway as an EXTERNAL FUNCTION.
#
# Request (what Snowflake POSTs, one batch of rows at a time):
#   {"data": [[row_number, transport_mode, distance_km, weight_kg, reefer], ...]}
# Response (what Snowflake expects back, same row numbers, same row count):
#   {"data": [[row_number, {result object}], ...]}
#
# Each result object is either
#   {"co2e_kg": ..., "tonne_km": ..., "factor_kg_per_tkm": ..., "reefer_uplift": ...,
#    "method": "KCC-GLEC-2026.1", "batch_rows": <rows in this batch>}
# or, for a row the service cannot score,
#   {"error": "<reason>", "method": ..., "batch_rows": ...}
#
# One bad row never fails the whole batch: it gets an "error" result and every
# other row in the batch is still scored. Only a malformed request returns 400.

import json

METHOD = "KCC-GLEC-2026.1"

# kg CO2e per tonne-km, well-to-wheel, by transport mode (illustrative values in the
# range published by the GLEC Framework; not for real carbon reporting).
EMISSION_FACTORS = {
    "ROAD": 0.0960,
    "RAIL": 0.0280,
    "SEA": 0.0160,
    "AIR": 0.6020,
}

# Refrigerated (reefer) equipment burns extra energy to keep cargo cold.
REEFER_UPLIFT = 1.20


def calculate(transport_mode, distance_km, weight_kg, reefer):
    """Score one shipment leg. Returns a dict with co2e_kg, or a dict with error."""
    mode = str(transport_mode).strip().upper() if transport_mode is not None else None
    if mode not in EMISSION_FACTORS:
        return {"error": "unsupported transport_mode: %s" % transport_mode}
    if distance_km is None or weight_kg is None:
        return {"error": "distance_km and weight_kg are required"}
    try:
        distance = float(distance_km)
        weight = float(weight_kg)
    except (TypeError, ValueError):
        return {"error": "distance_km and weight_kg must be numbers"}
    if distance <= 0 or weight <= 0:
        return {"error": "distance_km and weight_kg must be greater than 0"}

    factor = EMISSION_FACTORS[mode]
    uplift = REEFER_UPLIFT if reefer is True else 1.0
    tonne_km = (weight / 1000.0) * distance
    co2e_kg = round(tonne_km * factor * uplift, 3)
    return {
        "co2e_kg": co2e_kg,
        "tonne_km": round(tonne_km, 3),
        "factor_kg_per_tkm": factor,
        "reefer_uplift": uplift,
    }


def _response(status, payload):
    return {"statusCode": status, "body": json.dumps(payload)}


def lambda_handler(event, context):
    # With Lambda proxy integration, API Gateway passes the request body as a string.
    try:
        body = event.get("body") if isinstance(event, dict) else None
        if isinstance(body, str):
            body = json.loads(body)
        rows = body["data"]
        if not isinstance(rows, list):
            raise ValueError("data must be a list")
    except (TypeError, KeyError, ValueError) as exc:
        return _response(400, {"error": "malformed request: %s" % exc})

    batch_rows = len(rows)
    out = []
    for row in rows:
        row_number = row[0]
        args = (list(row[1:]) + [None] * 4)[:4]  # pad short rows so they fail cleanly
        try:
            result = calculate(*args)
        except Exception as exc:  # never let one row break the batch
            result = {"error": "unexpected error: %s" % exc}
        result["method"] = METHOD
        result["batch_rows"] = batch_rows
        out.append([row_number, result])

    return _response(200, {"data": out})
