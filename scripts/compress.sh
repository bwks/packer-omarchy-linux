#!/bin/bash
set -euo pipefail
: "${IMAGE_PATH:?Packer must provide IMAGE_PATH}"
qemu-img convert -O qcow2 -c "$IMAGE_PATH" "${IMAGE_PATH}.tmp"
mv "${IMAGE_PATH}.tmp" "$IMAGE_PATH"
qemu-img check "$IMAGE_PATH"
qemu-img info "$IMAGE_PATH"
