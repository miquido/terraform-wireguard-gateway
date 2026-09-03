output "gateway_public_ip" {
  value = aws_eip.this.public_ip
}

output "gateway_endpoint" {
  value = "${aws_eip.this.public_ip}:${var.wg_port}"
}

output "gateway_instance_id" {
  value = aws_instance.this.id
}

output "onprem_compose_snippet" {
  description = "Paste into the on-prem docker-compose.yml as a new service. See the snippet's own header comment for the two things you still need to fill in (WG_OFFICE_PRIVATE_KEY and this module's peer_public_key input)."
  value = templatefile("${path.module}/templates/onprem-compose.yml.tftpl", {
    gateway_public_key    = var.gateway_public_key
    gateway_endpoint      = "${aws_eip.this.public_ip}:${var.wg_port}"
    aws_cidr              = data.aws_vpc.this.cidr_block
    office_tunnel_address = var.office_tunnel_address
  })
}
