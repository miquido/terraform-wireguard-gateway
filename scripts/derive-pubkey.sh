#!/bin/sh
# Terraform `external` data source program: reads {"private_key": "..."} on stdin, prints
# {"public_key": "..."} on stdout. Pure function of an already-fixed input (no randomness),
# so this is a safe, idempotent use of `external` - not generating new key material, just
# deriving what wg-quick would compute internally anyway.
set -eu

PRIVATE_KEY=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["private_key"])')
PUBLIC_KEY=$(printf '%s' "$PRIVATE_KEY" | docker run --rm -i alpine sh -c 'apk add --no-cache wireguard-tools >/dev/null 2>&1; wg pubkey')

python3 -c "import json; print(json.dumps({'public_key': '$PUBLIC_KEY'}))"
