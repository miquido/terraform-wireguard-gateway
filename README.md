# wireguard-gateway

Poor-man's site-to-site VPN: a small EC2 instance that acts as a WireGuard gateway/router,
so that whatever's behind `route_table_ids` on the AWS side can reach `peer_cidr` on the
other end of the tunnel (an on-prem network, an office docker network, another cloud, ...),
and vice versa.

Deliberately **not** fully self-contained on the key-generation front: it takes both
`gateway_private_key` and `gateway_public_key` as inputs instead of generating them via a
`local-exec` provisioner, so this module has no hidden `docker`/`wg` dependency at plan
time and stays usable in CI. Generate the keypair once, keep it stable across applies:

```bash
docker run --rm alpine sh -c 'apk add --no-cache wireguard-tools >/dev/null; wg genkey' > gateway.key
docker run --rm -i alpine sh -c 'apk add --no-cache wireguard-tools >/dev/null; wg pubkey' < gateway.key > gateway.pub
```

## Two-apply flow (both sides need each other's public key)

1. First apply with `peer_public_key = ""` (the default) - stands up the gateway and gives
   you its public key/endpoint and a ready-to-paste on-prem docker-compose snippet via the
   `onprem_compose_snippet` output.
2. Generate a keypair on the on-prem side the same way as above, drop the snippet into the
   on-prem `docker-compose.yml`, deploy it. It prints its own public key to its container
   logs on first boot.
3. `terraform apply` again with `peer_public_key` set to that value. Done - traffic flows
   both ways.

## Usage - standalone (hand-rolled VPC, e.g. environments/rds-playground)

```hcl
module "wireguard" {
  source = "../../modules/wireguard-gateway"

  name            = "rds-playground-wireguard"
  vpc_id          = aws_vpc.rds.id
  subnet_id       = aws_subnet.rds[0].id
  route_table_ids = [aws_route_table.rds.id]

  peer_cidr = "172.20.0.0/16" # the on-prem docker network's subnet

  gateway_private_key = var.wg_gateway_private_key
  gateway_public_key  = var.wg_gateway_public_key
  peer_public_key     = var.wg_office_public_key
}
```

## Usage - with [miquido/terraform-vpc](https://github.com/miquido/terraform-vpc)

```hcl
module "vpc" {
  source      = "git::ssh://git@gitlab.com:miquido/terraform/terraform-vpc.git?ref=master"
  name        = "main"
  project     = "example"
  environment = "dev"
  azs         = ["eu-central-1a", "eu-central-1b"]
  nat_type    = "gateway-single"
}

module "wireguard" {
  source = "../../modules/wireguard-gateway"

  name      = "office-tunnel"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnet_ids[0] # needs a stable public endpoint

  # Whatever needs to reach the on-prem side - usually the private route table(s), not
  # the public ones.
  route_table_ids = module.vpc.private_route_table_ids

  peer_cidr = "10.50.0.0/16" # the on-prem network

  gateway_private_key = var.wg_gateway_private_key
  gateway_public_key  = var.wg_gateway_public_key
  peer_public_key     = var.wg_office_public_key
}
```

## `peer_cidr` - pick the narrowest thing that's actually true

This is *what's reachable* on the other end, not just "the office network". If the on-prem
side is a single docker-compose project's own bridge network (as in `rds-playground`), use
*that* network's subnet, not the whole office LAN - the on-prem WireGuard container can
only forward into whatever network it's actually joined to. Two docker-specific gotchas
that cost real debugging time building this the first time:

- If that docker network already existed before you decided to route into it, **pin its
  subnet explicitly** (`networks.default.ipam.config` in the on-prem docker-compose.yml) -
  otherwise you're routing into whatever Docker happened to allocate, and it won't change
  to match on a normal `docker compose up` (only a full stack recreate re-IPAMs an
  existing network).
- The on-prem WireGuard container needs a `MASQUERADE` rule for traffic it forwards onto
  that docker network (`iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE`, already in
  `onprem_compose_snippet`). Without it, the docker network's other containers have no
  route back to the tunnel's point-to-point subnet, so replies never make it back.

## The route-table gotcha this module works around

If you add `aws_route.to_peer`'s destination to a route table that *also* has an inline
`route { ... }` block (rather than being assembled purely from standalone `aws_route`
resources), the inline block treats itself as the sole source of truth and **deletes this
module's route on every apply of that other resource** - not just when you change
something related. Symptom: the tunnel works right after you provision it, then
mysteriously stops being reachable after some unrelated `terraform apply` elsewhere in the
same route table, with no error - the route data silently disappears. If you're wiring
this into an existing route table, make sure it doesn't have inline `route` blocks.
