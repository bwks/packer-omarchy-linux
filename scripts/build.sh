#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .tmp
export PACKER_CACHE_DIR="$PWD/packer_cache"
build_work=$(mktemp -d "$PWD/.tmp/build.XXXXXX")
trap 'rm -rf "$build_work"' EXIT
ssh-keygen -q -t ed25519 -f "$build_work/key" -N '' -C packer-build
export PKR_VAR_ssh_public_key
PKR_VAR_ssh_public_key=$(cat "$build_work/key.pub")
export PKR_VAR_ssh_private_key_file="$build_work/key"
export PKR_VAR_build_password
PKR_VAR_build_password=$(openssl rand -hex 24)
export PKR_VAR_build_password_hash
PKR_VAR_build_password_hash=$(printf '%s\n' "$PKR_VAR_build_password" | openssl passwd -6 -stdin)
packer init omarchy.pkr.hcl
packer build "$@" omarchy.pkr.hcl
