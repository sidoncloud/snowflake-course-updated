#!/usr/bin/env bash
# Generate an RSA key pair for Snowflake key-pair authentication.
# The Kafka connector authenticates with the PRIVATE key; Snowflake stores the
# PUBLIC key on the user via RSA_PUBLIC_KEY. Run this once, in the folder where
# you keep the lab files.
#
#   Mac / Linux : open a terminal in this folder and run  bash generate-key-pair.sh
#   Windows     : Command Prompt and PowerShell can't run this. Use Git Bash
#                 (comes with Git for Windows and includes openssl): right-click
#                 this folder in File Explorer > "Open Git Bash here", then run
#                 bash generate-key-pair.sh   (WSL works the same way.)
#
# Check openssl is there first with:  openssl version
# Linux without openssl: sudo apt install openssl  (or sudo dnf install openssl)
set -euo pipefail

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl not found. On Windows run this from Git Bash or WSL."
  echo "On Linux install it with: sudo apt install openssl (or sudo dnf install openssl)"
  exit 1
fi

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
