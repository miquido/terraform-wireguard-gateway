#!/bin/sh
# Generates both WireGuard keypairs this module's tunnel needs and prints them labeled by
# where each one actually goes - the module's own input variable names, or the generic
# env var name onprem-compose.yml.tftpl expects. Not tied to any specific consumer project;
# wherever "your CI/CD variables" or "your terraform.tfvars" is mentioned, that's wherever
# you're actually calling this module from.
set -eu

docker run --rm alpine sh -c '
  apk add --no-cache wireguard-tools >/dev/null 2>&1

  gateway_priv=$(wg genkey)
  gateway_pub=$(echo "$gateway_priv" | wg pubkey)
  peer_priv=$(wg genkey)
  peer_pub=$(echo "$peer_priv" | wg pubkey)

  echo "==> this module'\''s inputs (terraform.tfvars or wherever you call the module from)"
  echo "gateway_private_key = \"$gateway_priv\""
  echo "peer_public_key     = \"$peer_pub\""
  echo
  echo "==> on-prem side (onprem_compose_snippet output) - wire this in as WG_OFFICE_PRIVATE_KEY"
  echo "    (a CI/CD variable, a .env entry, whatever your on-prem deploy uses)"
  echo "WG_OFFICE_PRIVATE_KEY=$peer_priv"
  echo
  echo "==> sanity check only, not pasted anywhere - after terraform apply, \`terraform"
  echo "    output gateway_public_key\` should equal this, and the on-prem container'\''s own"
  echo "    logs on first boot should print this exact peer public key too"
  echo "gateway public key: $gateway_pub"
  echo "peer public key:    $peer_pub"
'
