# [2.1.0](https://gitlab.miquido.com/miquido/terraform/terraform-wireguard-gateway/compare/v2.0.0...v2.1.0) (2026-09-03)


### Features

* add gen-keys.sh to generate both tunnel keypairs at once ([6da9225](https://gitlab.miquido.com/miquido/terraform/terraform-wireguard-gateway/commit/6da92253568240f757d52a3cb89142856c0b36f6))

# [2.0.0](https://gitlab.miquido.com/miquido/terraform/terraform-wireguard-gateway/compare/v1.0.1...v2.0.0) (2026-09-03)


* fix!: derive gateway_public_key internally instead of requiring it as input ([ca65c51](https://gitlab.miquido.com/miquido/terraform/terraform-wireguard-gateway/commit/ca65c51094a7750c1bc247ef1f3f7697ec7b78b5))


### BREAKING CHANGES

* gateway_public_key is no longer a module input. Remove it
from any module block; it's now available as the gateway_public_key output
instead. Requires `docker` wherever terraform plan/apply runs.

## [1.0.1](https://gitlab.miquido.com/miquido/terraform/terraform-wireguard-gateway/compare/v1.0.0...v1.0.1) (2026-09-03)


### Bug Fixes

* use count instead of for_each for the peer route ([2bc7457](https://gitlab.miquido.com/miquido/terraform/terraform-wireguard-gateway/commit/2bc7457b9939bcfc9f33b14cd17341bb00459640))

# 1.0.0 (2026-09-03)


### Features

* initial import of the wireguard-gateway module ([19021f0](https://gitlab.miquido.com/miquido/terraform/terraform-wireguard-gateway/commit/19021f084faea7ea48bfe0d08d6b3ea6dfe0440e))
