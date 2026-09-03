output "gateway_public_ip" {
  value = aws_eip.this.public_ip
}

output "gateway_endpoint" {
  value = "${aws_eip.this.public_ip}:${var.wg_port}"
}

output "gateway_instance_id" {
  value = aws_instance.this.id
}

output "gateway_public_key" {
  description = "Derived from gateway_private_key. This is what the on-prem peer's config needs as its WG_AWS_PUBLIC_KEY - already baked into onprem_compose_snippet, exposed here too in case you need it standalone."
  value       = data.external.gateway_pubkey.result.public_key
}

output "onprem_compose_snippet" {
  description = "Paste into the on-prem docker-compose.yml as a new service. See the snippet's own header comment for the one thing you still need to fill in (WG_OFFICE_PRIVATE_KEY)."
  value = templatefile("${path.module}/templates/onprem-compose.yml.tftpl", {
    gateway_public_key    = data.external.gateway_pubkey.result.public_key
    gateway_endpoint      = "${aws_eip.this.public_ip}:${var.wg_port}"
    aws_cidr              = data.aws_vpc.this.cidr_block
    office_tunnel_address = var.office_tunnel_address
  })
}
