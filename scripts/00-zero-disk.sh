#!/bin/bash
set -euo pipefail
# Btrfs snapshots and compression make filling free space ineffective. Discard
# unused blocks instead, then let qemu-img compress the remaining clusters.
sync
fstrim -av
