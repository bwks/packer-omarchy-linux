#!/bin/bash
set -euo pipefail
# Arch requires a full upgrade when refreshing package databases.
OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Syu --noconfirm --needed cloud-init
install -d /etc/cloud/cloud.cfg.d
cat >/etc/cloud/cloud.cfg.d/90-sherpa.cfg <<'EOF'
system_info:
  default_user:
    name: sherpa
    lock_passwd: true
    gecos: Sherpa
    groups: [wheel]
    sudo: ["ALL=(ALL) ALL"]
    shell: /bin/bash
disable_root: true
ssh_pwauth: false
# Keep Omarchy's NetworkManager setup; cloud-init configures identity and users.
network:
  config: disabled
EOF
systemctl enable cloud-init-local.service cloud-init-network.service cloud-config.service cloud-final.service
if [[ -f /usr/lib/systemd/system/cloud-init-main.service ]]; then
  systemctl enable cloud-init-main.service
fi
systemctl enable sshd.service
ufw allow 22/tcp
# Skip Limine's default five-second menu wait on unattended VMs.
sed -i -E '/^[[:space:]]*#?[[:space:]]*timeout[[:space:]]*:/Id' /boot/limine.conf
sed -i '1i timeout: 0' /boot/limine.conf
# Needed by the remaining Packer provisioners and shutdown; removed on shutdown.
printf '%s\n' 'sherpa ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/zz-packer-sherpa
chmod 0440 /etc/sudoers.d/zz-packer-sherpa
visudo -cf /etc/sudoers.d/zz-packer-sherpa
