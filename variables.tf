variable "name" {
  type        = string
  default     = "wireguard"
  description = "Prefix used for all resource names/tags created by this module."
}

variable "vpc_id" {
  type        = string
  description = "VPC to deploy the gateway into. From terraform-vpc: module.vpc.vpc_id."
}

variable "subnet_id" {
  type        = string
  description = "Subnet to launch the gateway instance into - must route to an Internet Gateway (needs a stable public endpoint for the peer to dial). From terraform-vpc: module.vpc.public_subnet_ids[0]."
}

variable "route_table_ids" {
  type        = list(string)
  description = "Route table(s) that need a route to peer_cidr added, pointing at this gateway. Typically the route table(s) for whatever needs to reach the remote/on-prem side - e.g. an RDS subnet group's route table, or from terraform-vpc: module.vpc.private_route_table_ids."
}

variable "peer_cidr" {
  type        = string
  description = "CIDR of the network on the other side of the tunnel (the on-prem/office network, or the specific docker bridge subnet within it) that should become reachable from route_table_ids."
}

variable "gateway_private_key" {
  type        = string
  sensitive   = true
  description = "WireGuard private key for this AWS-side gateway. Generate once with `wg genkey` (e.g. `docker run --rm alpine sh -c 'apk add --no-cache wireguard-tools >/dev/null; wg genkey'`) and keep it stable across applies - this module does not generate it, to keep the module usable in CI without a docker/wg-tools dependency at plan time."
}

variable "gateway_public_key" {
  type        = string
  description = "Public counterpart of gateway_private_key (`wg pubkey <<< $private_key`). Kept as a separate input rather than derived, for the same CI-portability reason - deriving it would require shelling out to `wg` at plan time."
}

variable "peer_public_key" {
  type        = string
  default     = ""
  description = "WireGuard public key of the on-prem/office peer. Leave empty for a first apply to get the gateway stood up and its own public key/endpoint as output, then fill this in once you have the peer's key and apply again."
}

variable "wg_port" {
  type        = number
  default     = 51820
  description = "UDP port WireGuard listens on."
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to reach the WireGuard UDP port. Defaults wide open since WireGuard silently drops unauthenticated packets regardless of source; narrow this down if the peer's source IP is static."
}

variable "instance_type" {
  type        = string
  default     = "t4g.nano"
  description = "Gateway instance size. It only routes/encrypts packets, t4g.nano is plenty for test/sandbox traffic."
}

variable "gateway_tunnel_address" {
  type        = string
  default     = "10.100.0.1/30"
  description = "Address of the gateway's own wg0 interface, in the point-to-point tunnel subnet (distinct from both real networks on either side)."
}

variable "office_tunnel_address" {
  type        = string
  default     = "10.100.0.2/30"
  description = "Address the on-prem peer's wg0 interface should use, in the same point-to-point tunnel subnet as gateway_tunnel_address. Only used to render onprem_compose_snippet - has no effect on this module's own resources."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags applied to all resources created by this module."
}
