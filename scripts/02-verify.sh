#!/bin/bash
# Boot the output omarchy image and verify all installed services are working.
# Uses a QEMU copy-on-write overlay so the original image is never modified.
set -euo pipefail

IMAGE="${1:-output/omarchy.qcow2}"
SSH_PORT=${SSH_PORT:-2222}
FW_CODE=${FW_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
FW_VARS=${FW_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}

if [ ! -f "$IMAGE" ]; then
  echo "Error: image not found at $IMAGE"
  exit 1
fi

TMPDIR_WORK=$(mktemp -d)
OVERLAY="$TMPDIR_WORK/overlay.qcow2"
VERIFY_KEY="$TMPDIR_WORK/verify_key"
QEMU_PID_FILE="$TMPDIR_WORK/qemu.pid"

cleanup() {
  echo ""
  echo "Cleaning up..."
  if [ -f "$QEMU_PID_FILE" ]; then
    QEMU_PID=$(cat "$QEMU_PID_FILE")
    kill "$QEMU_PID" 2>/dev/null || true
    # Wait for qemu to actually exit
    for i in $(seq 1 10); do
      kill -0 "$QEMU_PID" 2>/dev/null || break
      sleep 1
    done
  fi
  rm -rf "$TMPDIR_WORK" "$OVERLAY"
}
trap cleanup EXIT

echo "=== omarchy verification ==="
echo "Image: $IMAGE"

echo ""

# Generate a temporary SSH keypair for this verify session
ssh-keygen -t ed25519 -f "$VERIFY_KEY" -N "" -C "omarchy-verify" -q

# Build a cloud-init seed ISO so cloud-init can configure the sherpa user on boot
cat > "$TMPDIR_WORK/user-data" << USERDATA
#cloud-config
users:
  - name: sherpa
    ssh_authorized_keys:
      - $(cat "${VERIFY_KEY}.pub")
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
ssh_pwauth: false
USERDATA

cat > "$TMPDIR_WORK/meta-data" << METADATA
instance-id: verify-$(date +%s)
local-hostname: omarchy-verify
METADATA

genisoimage \
  -output "$TMPDIR_WORK/seed.iso" \
  -volid cidata \
  -joliet -rock \
  "$TMPDIR_WORK/user-data" \
  "$TMPDIR_WORK/meta-data" \
  2>/dev/null

echo "Created cloud-init seed ISO."

cp "$FW_VARS" "$TMPDIR_WORK/vars.fd"

# Create a copy-on-write overlay — original image is never touched
qemu-img create \
  -f qcow2 \
  -b "$(realpath "$IMAGE")" \
  -F qcow2 \
  "$OVERLAY" \
  > /dev/null

echo "Created QEMU overlay."
echo "Booting VM on SSH port $SSH_PORT..."

qemu-system-x86_64 \
  -m 4096 \
  -cpu host \
  -smp 2 \
  -enable-kvm \
  -machine q35 \
  -drive "if=pflash,format=raw,readonly=on,file=$FW_CODE" \
  -drive "if=pflash,format=raw,file=$TMPDIR_WORK/vars.fd" \
  -drive "file=$OVERLAY,if=virtio,format=qcow2" \
  -drive "file=$TMPDIR_WORK/seed.iso,if=virtio,format=raw,readonly=on" \
  -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
  -device virtio-net-pci,netdev=net0 \
  -display none \
  -serial "file:$TMPDIR_WORK/serial.log" \
  -monitor null \
  -daemonize \
  -pidfile "$QEMU_PID_FILE"

echo "VM started (PID $(cat "$QEMU_PID_FILE"))."
echo ""
echo "Waiting for SSH..."

SSH_OPTS="-o UserKnownHostsFile=$TMPDIR_WORK/known_hosts -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o LogLevel=ERROR -p $SSH_PORT -i $VERIFY_KEY"

for i in $(seq 1 60); do
  if ssh $SSH_OPTS sherpa@localhost "true" 2>/dev/null; then
    echo "SSH ready after ~$((i * 5))s."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "Error: timed out waiting for SSH."
    cat "$TMPDIR_WORK/serial.log" >&2
    exit 1
  fi
  printf "."
  sleep 5
done

echo ""
echo "--- Running verification checks ---"
echo ""

ssh $SSH_OPTS sherpa@localhost "bash -s" << 'CHECKS'
set -e

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; exit 1; }

# First-boot configuration must complete without degraded or failed status.
sudo timeout 180 cloud-init status --wait
. /etc/os-release
[ "$ID" = omarchy ] && pass "Omarchy Linux" || fail "unexpected operating system: $ID"
pacman -Q omarchy omarchy-settings cloud-init >/dev/null && pass "base Omarchy and cloud-init installed"
[ -s /etc/machine-id ] && pass "machine-id regenerated" || fail "machine-id missing"
[ "$(hostname)" = omarchy-verify ] && pass "cloud-init hostname applied" || fail "hostname unchanged"
[ ! -e /etc/sudoers.d/zz-packer-sherpa ] && pass "build sudo rule removed" || fail "build sudo rule remains"
[ "$(wc -l < ~/.ssh/authorized_keys)" -eq 1 ] && pass "only first-boot SSH key present" || fail "unexpected SSH keys"
for unit in cloud-init-local cloud-init-network cloud-config cloud-final sshd NetworkManager; do
  systemctl is-enabled --quiet "$unit.service" || fail "$unit not enabled"
done
systemctl is-active --quiet sshd NetworkManager && pass "SSH and networking active"
sudo test -s /etc/ssh/ssh_host_ed25519_key && pass "SSH host keys regenerated"
sudo awk -F: '$1 == "sherpa" {exit ($2 != "!")}' /etc/shadow && pass "build password removed"
sudo test ! -e /var/lib/omarchy/provisioning && pass "installer credentials removed"
sudo grep -qx 'timeout: 0' /boot/limine.conf && pass "Limine menu timeout disabled" || fail "Limine menu timeout remains"
sudo bash -s <<'SNAPSHOTS'
set -euo pipefail
mkdir -p /run/verify-top
mount -o subvolid=5 "$(findmnt -no SOURCE / | sed 's/\[.*//')" /run/verify-top
trap 'umount /run/verify-top' EXIT
test -d /run/verify-top/@factory
test ! -s /run/verify-top/@factory/etc/machine-id
test ! -e /run/verify-top/@factory/etc/sudoers.d/zz-packer-sherpa
awk -F: '$1 == "sherpa" {found=1; if ($2 != "!") exit 1} END {if (!found) exit 1}' /run/verify-top/@factory/etc/shadow
for shadow in /run/verify-top/@/.snapshots/*/snapshot/etc/shadow; do
  [[ -f $shadow ]] || continue
  awk -F: '$1 == "sherpa" && $2 != "!" {exit 1}' "$shadow"
done
SNAPSHOTS
pass "factory snapshot and rollback snapshots contain no build password"

echo ""
echo "All checks passed."
CHECKS

echo ""
echo "Shutting down verify VM..."
ssh $SSH_OPTS sherpa@localhost "sudo shutdown -P now" 2>/dev/null || true

# Give it a moment to shut down
for i in $(seq 1 15); do
  QEMU_PID=$(cat "$QEMU_PID_FILE" 2>/dev/null || echo "")
  [ -z "$QEMU_PID" ] && break
  kill -0 "$QEMU_PID" 2>/dev/null || break
  sleep 1
done

echo "Done."
