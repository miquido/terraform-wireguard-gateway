# Poor-man's site-to-site VPN: a small EC2 instance acts as a WireGuard gateway + router,
# so anything using route_table_ids can reach peer_cidr on the other side of the tunnel,
# and vice versa. See README.md for the on-prem side (a WireGuard container joined to
# whatever network peer_cidr actually is).

data "aws_vpc" "this" {
  id = var.vpc_id
}

# Derives the gateway's own public key from gateway_private_key instead of asking for it
# as a separate input - it's a pure function of an already-fixed value (no randomness), so
# this is a safe use of `external`, not the kind of "generates new state on every apply"
# footgun `local-exec`/`external` usually are. Requires `docker` wherever you run
# terraform plan/apply - fine for interactive use, a real constraint if you run this
# module from a docker-less CI runner.
data "external" "gateway_pubkey" {
  program = ["${path.module}/scripts/derive-pubkey.sh"]
  query = {
    private_key = var.gateway_private_key
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-arm64"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "this" {
  name = var.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = var.name
  role = aws_iam_role.this.name
}

resource "aws_security_group" "this" {
  # name_prefix (not name) + create_before_destroy: a fixed name means any forced
  # replacement (e.g. changing the description, or an ingress/egress block in a way AWS
  # can't update in place) deadlocks - Terraform's default destroy-then-create order can't
  # delete the old SG while the instance is still attached to it, and can't reattach the
  # instance to a new one that doesn't exist yet because the name is already taken.
  name_prefix = "${var.name}-"
  description = "WireGuard gateway for ${var.name}"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    description = "WireGuard"
    from_port   = var.wg_port
    to_port     = var.wg_port
    protocol    = "udp"
    cidr_blocks = var.allowed_ingress_cidrs
  }

  # This instance is a router (source_dest_check = false) - SGs filter transit traffic
  # too, not just packets addressed to the instance itself, so without this the route
  # table entries alone don't get traffic past the gateway's own SG.
  ingress {
    description = "Transit traffic being forwarded through the tunnel"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  # Has to forward traffic that isn't addressed to itself (the whole point of this
  # instance).
  source_dest_check = false

  # Flush-left on purpose: this is a heredoc-within-a-heredoc, and Terraform's `<<-` dedent
  # would otherwise leave leading spaces on the nested "WGEOF" bash terminator, which
  # breaks bash's heredoc parsing (it requires the closing marker at column 0).
  user_data = <<-EOF
#!/bin/bash
dnf install -y wireguard-tools
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf

install -d -m 700 /etc/wireguard
cat > /etc/wireguard/wg0.conf <<WGEOF
[Interface]
Address = ${var.gateway_tunnel_address}
ListenPort = ${var.wg_port}
PrivateKey = ${var.gateway_private_key}

[Peer]
PublicKey = ${var.peer_public_key}
AllowedIPs = ${var.peer_cidr}
PersistentKeepalive = 25
WGEOF
chmod 600 /etc/wireguard/wg0.conf

systemctl enable --now wg-quick@wg0
EOF

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"

  tags = merge(var.tags, { Name = var.name })
}

# One per route table - each needs its own route pointing traffic for peer_cidr at this
# gateway's ENI. Kept as standalone aws_route resources rather than inline `route` blocks
# on whatever route table resource you already have: if that table also has an inline
# `route { ... }` argument, it treats itself as the sole source of truth and deletes
# anything not declared there on every apply, including this one.
#
# count, not for_each: route_table_ids commonly comes straight from a VPC module's output
# (e.g. terraform-vpc's public_route_table_ids) on a from-scratch apply, where the route
# table IDs aren't known until apply. for_each over a set built from unknown values fails
# at plan time ("Invalid for_each argument"); count only needs the list's length, which is
# known even when its elements aren't.
resource "aws_route" "to_peer" {
  count = length(var.route_table_ids)

  route_table_id         = var.route_table_ids[count.index]
  destination_cidr_block = var.peer_cidr
  network_interface_id   = aws_instance.this.primary_network_interface_id
}
