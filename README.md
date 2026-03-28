# Infrastructure

NixOS + Incus GitOps repo for Thor's container infrastructure.

## Quick Start

```bash
# Check container status
incus list

# Deploy to workbench
./scripts/deploy.sh workbench

# Build only (no apply)
./scripts/deploy.sh workbench --build-only
```

## Structure

- `flake.nix` — entry point, pins nixpkgs 25.11
- `nixos/modules/` — shared NixOS modules
- `nixos/hosts/workbench/` — workbench-specific config
- `secrets/` — sops-encrypted secrets (see docs/ARCHITECTURE.md)
- `scripts/` — bootstrap and deploy helpers

## See Also

- [Architecture](docs/ARCHITECTURE.md) — full stack diagram and workflow
