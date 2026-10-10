#!/bin/bash
set -euo pipefail
usermod -p '!' sherpa
passwd -l root
rm -f /home/sherpa/.ssh/authorized_keys /home/sherpa/.bash_history /root/.bash_history
rm -f /etc/ssh/ssh_host_*
rm -rf /var/lib/omarchy/provisioning
cloud-init clean --logs --seed
# An empty ID generates a new identity without applying Arch's first-boot
# presets, which would disable the services we explicitly enabled.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
systemctl stop systemd-random-seed.service
rm -f /var/lib/systemd/random-seed /var/lib/systemd/credential.secret
rm -f /var/lib/NetworkManager/*.lease /var/lib/NetworkManager/secret_key

# Replace the installer's factory snapshot with our sealed base so reset cannot
# restore build credentials and also retains cloud-init. The temporary sudo
# rule is removed from the snapshot now and from the live root on shutdown.
install -d /run/packer-top
mount -o subvolid=5 "$(findmnt -no SOURCE / | sed 's/\[.*//')" /run/packer-top
trap 'umount /run/packer-top' EXIT
if [[ -d /run/packer-top/@factory ]]; then
  btrfs subvolume delete /run/packer-top/@factory
fi
btrfs subvolume snapshot /run/packer-top/@ /run/packer-top/@factory
rm -f /run/packer-top/@factory/etc/sudoers.d/zz-packer-sherpa
btrfs property set -ts /run/packer-top/@factory ro true
sync
fstrim -av
