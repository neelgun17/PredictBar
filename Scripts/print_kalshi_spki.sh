#!/bin/bash
# Prints the SHA-256 SPKI hashes for the full TLS certificate chain of
# api.elections.kalshi.com. Use the output to refresh the pinned values
# in Services/PinnedURLSession.swift if Kalshi rotates their CA.
#
# We intentionally pin the *intermediate* CA (Amazon RSA 2048 M02) rather
# than the leaf cert because AWS Certificate Manager rotates the leaf every
# ~90 days; the intermediate is stable for years.
set -euo pipefail

HOST="api.elections.kalshi.com"
PORT=443
CHAIN=$(mktemp)
trap 'rm -f "$CHAIN"' EXIT

echo | openssl s_client -servername "$HOST" -connect "$HOST:$PORT" -showcerts 2>/dev/null > "$CHAIN"

python3 - "$CHAIN" <<'PY'
import re, subprocess, base64, hashlib, sys
with open(sys.argv[1]) as f: data = f.read()
certs = re.findall(r'-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----', data, re.S)
for i, c in enumerate(certs):
    cb = c.encode()
    subj = subprocess.run(['openssl','x509','-noout','-subject','-issuer'], input=cb, capture_output=True).stdout.decode().strip()
    pub = subprocess.run(['openssl','x509','-pubkey','-noout'], input=cb, capture_output=True).stdout
    der = subprocess.run(['openssl','pkey','-pubin','-outform','DER'], input=pub, capture_output=True).stdout
    print(f"--- cert {i} ---")
    print(subj)
    print("SPKI SHA-256 (base64):", base64.b64encode(hashlib.sha256(der).digest()).decode())
    print()
PY
