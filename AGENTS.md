# packer-omarchy-linux

Build the standard Omarchy image for `sherpa` with cloud-init. Keep added image
contents limited to cloud-init and the configuration needed for VM provisioning.
Use `omarchy.pkr.hcl`, installer inputs in `http/`, and Bash scripts in `scripts/`.

Preserve user changes. Keep generated credentials, caches, seeds, and output
images ignored. Never commit build passwords or private keys. Retain strict
Bash mode. Run `bash -n scripts/*.sh`, Packer formatting and validation, and
`git diff --check`. When resources permit, build and run `02-verify.sh`; report
any validation that could not be completed. Maintain UEFI boot and unique
first-boot identity; scrub build credentials from Btrfs snapshots as well as
the live root. Update README instructions with behavior changes.
