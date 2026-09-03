# terraform-wireguard-gateway <a href="https://miquido.com"><img align="right" src="https://cdn.miquido.dev/miquido-logo.png" width="150" /></a>

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

## Development

```bash
make init   # run once after cloning
make readme # regenerate README.md
make lint   # lint terraform code
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

## Usage - standalone (hand-rolled VPC)

```hcl
module "wireguard" {
  source = "git::ssh://git@gitlab.miquido.com/miquido/terraform/terraform-wireguard-gateway.git?ref=main"

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

## Usage - with [terraform-vpc](https://gitlab.miquido.com/miquido/terraform/terraform-vpc)

```hcl
module "vpc" {
  source      = "git::ssh://git@gitlab.miquido.com/miquido/terraform/terraform-vpc.git?ref=main"
  name        = "main"
  project     = "example"
  environment = "dev"
  azs         = ["eu-central-1a", "eu-central-1b"]
  nat_type    = "gateway-single"
}

module "wireguard" {
  source = "git::ssh://git@gitlab.miquido.com/miquido/terraform/terraform-wireguard-gateway.git?ref=main"

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
side is a single docker-compose project's own bridge network (as in the `rds-playground`
sandbox this module was extracted from), use *that* network's subnet, not the whole office
LAN - the on-prem WireGuard container can only forward into whatever network it's actually
joined to. Two docker-specific gotchas that cost real debugging time building this the
first time:

- If that docker network already existed before you decided to route into it, **pin its
  subnet explicitly** (`networks.default.ipam.config` in the on-prem docker-compose.yml) -
  otherwise you're routing into whatever Docker happened to allocate, and it won't change
  to match on a normal `docker compose up` (only a full stack recreate re-IPAMs an
  existing network).
- The on-prem WireGuard container needs a `MASQUERADE` rule for traffic it forwards onto
  that docker network (`iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE`, already in
  `onprem_compose_snippet`). Without it, the docker network's other containers have no
  route back to the tunnel's point-to-point subnet, so replies never make it back.

## Two gotchas this module already works around

- **Route table ownership.** If you add `aws_route.to_peer`'s destination to a route table
  that *also* has an inline `route { ... }` block (rather than being assembled purely from
  standalone `aws_route` resources), the inline block treats itself as the sole source of
  truth and **deletes this module's route on every apply of that other resource** - not
  just when you change something related. Symptom: the tunnel works right after you
  provision it, then mysteriously stops being reachable after some unrelated
  `terraform apply` elsewhere in the same route table, with no error - the route data
  silently disappears. If you're wiring this into an existing route table, make sure it
  doesn't have inline `route` blocks.
- **Security group replacement deadlock.** The gateway's security group uses `name_prefix`
  (not `name`) with `create_before_destroy`. A fixed `name` plus a forced replacement (e.g.
  editing the description, or an ingress/egress block change AWS can't apply in place)
  deadlocks: Terraform's default destroy-then-create order can't delete the old SG while
  the instance is still attached to it, and can't create the replacement under the same
  name while the old one still exists. Keep both of those if you ever touch the security
  group resource.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.62.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eip.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_iam_instance_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_route.to_peer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_ingress_cidrs"></a> [allowed\_ingress\_cidrs](#input\_allowed\_ingress\_cidrs) | CIDRs allowed to reach the WireGuard UDP port. Defaults wide open since WireGuard silently drops unauthenticated packets regardless of source; narrow this down if the peer's source IP is static. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_gateway_private_key"></a> [gateway\_private\_key](#input\_gateway\_private\_key) | WireGuard private key for this AWS-side gateway. Generate once with `wg genkey` (e.g. `docker run --rm alpine sh -c 'apk add --no-cache wireguard-tools >/dev/null; wg genkey'`) and keep it stable across applies - this module does not generate it, to keep the module usable in CI without a docker/wg-tools dependency at plan time. | `string` | n/a | yes |
| <a name="input_gateway_public_key"></a> [gateway\_public\_key](#input\_gateway\_public\_key) | Public counterpart of gateway\_private\_key (`wg pubkey <<< $private_key`). Kept as a separate input rather than derived, for the same CI-portability reason - deriving it would require shelling out to `wg` at plan time. | `string` | n/a | yes |
| <a name="input_gateway_tunnel_address"></a> [gateway\_tunnel\_address](#input\_gateway\_tunnel\_address) | Address of the gateway's own wg0 interface, in the point-to-point tunnel subnet (distinct from both real networks on either side). | `string` | `"10.100.0.1/30"` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Gateway instance size. It only routes/encrypts packets, t4g.nano is plenty for test/sandbox traffic. | `string` | `"t4g.nano"` | no |
| <a name="input_name"></a> [name](#input\_name) | Prefix used for all resource names/tags created by this module. | `string` | `"wireguard"` | no |
| <a name="input_office_tunnel_address"></a> [office\_tunnel\_address](#input\_office\_tunnel\_address) | Address the on-prem peer's wg0 interface should use, in the same point-to-point tunnel subnet as gateway\_tunnel\_address. Only used to render onprem\_compose\_snippet - has no effect on this module's own resources. | `string` | `"10.100.0.2/30"` | no |
| <a name="input_peer_cidr"></a> [peer\_cidr](#input\_peer\_cidr) | CIDR of the network on the other side of the tunnel (the on-prem/office network, or the specific docker bridge subnet within it) that should become reachable from route\_table\_ids. | `string` | n/a | yes |
| <a name="input_peer_public_key"></a> [peer\_public\_key](#input\_peer\_public\_key) | WireGuard public key of the on-prem/office peer. Leave empty for a first apply to get the gateway stood up and its own public key/endpoint as output, then fill this in once you have the peer's key and apply again. | `string` | `""` | no |
| <a name="input_route_table_ids"></a> [route\_table\_ids](#input\_route\_table\_ids) | Route table(s) that need a route to peer\_cidr added, pointing at this gateway. Typically the route table(s) for whatever needs to reach the remote/on-prem side - e.g. an RDS subnet group's route table, or from terraform-vpc: module.vpc.private\_route\_table\_ids. | `list(string)` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Subnet to launch the gateway instance into - must route to an Internet Gateway (needs a stable public endpoint for the peer to dial). From terraform-vpc: module.vpc.public\_subnet\_ids[0]. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags applied to all resources created by this module. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC to deploy the gateway into. From terraform-vpc: module.vpc.vpc\_id. | `string` | n/a | yes |
| <a name="input_wg_port"></a> [wg\_port](#input\_wg\_port) | UDP port WireGuard listens on. | `number` | `51820` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_gateway_endpoint"></a> [gateway\_endpoint](#output\_gateway\_endpoint) | n/a |
| <a name="output_gateway_instance_id"></a> [gateway\_instance\_id](#output\_gateway\_instance\_id) | n/a |
| <a name="output_gateway_public_ip"></a> [gateway\_public\_ip](#output\_gateway\_public\_ip) | n/a |
| <a name="output_onprem_compose_snippet"></a> [onprem\_compose\_snippet](#output\_onprem\_compose\_snippet) | Paste into the on-prem docker-compose.yml as a new service. See the snippet's own header comment for the two things you still need to fill in (WG\_OFFICE\_PRIVATE\_KEY and this module's peer\_public\_key input). |
<!-- END_TF_DOCS -->

## License

[MIT](LICENSE)
