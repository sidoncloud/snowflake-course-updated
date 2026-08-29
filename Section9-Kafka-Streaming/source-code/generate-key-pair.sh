#!/usr/bin/env bash
# Generate an RSA key pair for Snowflake key-pair authentication.
# The Kafka connector authenticates with the PRIVATE key; Snowflake stores the
# PUBLIC key on the user via RSA_PUBLIC_KEY. Run this once, in the folder where
# you keep the lab files.
set -euo pipefail

# 1. Private key, PKCS8, unencrypted. This is the key the connector will use.
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt

# 2. Public key derived from the private key.
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub

# 3. The PUBLIC key as a single line with the header/footer stripped. Paste this
#    value into RSA_PUBLIC_KEY in snowflake-kafka-setup.sql.
echo
echo "===== RSA_PUBLIC_KEY (paste into the CREATE USER statement) ====="
grep -v "BEGIN\|END" rsa_key.pub | tr -d '\n'; echo
echo

# 4. The PRIVATE key as a single line with the header/footer stripped. Paste this
#    value into snowflake.private.key in snowflake-sink-connector.json.
echo "===== snowflake.private.key (paste into the connector config) ====="
grep -v "BEGIN\|END" rsa_key.p8 | tr -d '\n'; echo
echo
echo "Keep rsa_key.p8 private. Never commit it to source control."
