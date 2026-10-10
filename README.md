# packer-omarchy-linux

Builds a standard Omarchy 4.0.4 installation for `sherpa`, with cloud-init
added, as a compressed 40 GiB qcow2 image. Uses the same Packer/QEMU, `http/`,
and `scripts/` layout as the local `packer-devbox-linux` project.

The official ISO installs Omarchy's normal desktop, applications, Btrfs layout,
and Limine bootloader. Cloud-init is the only extra package requested by this
project. SSH is enabled and allowed through Omarchy's firewall. NetworkManager
continues managing networking; cloud-init network rendering is disabled.
The disk is unencrypted so instances can boot unattended. The `sherpa` and root
passwords are locked in the final image; supply SSH keys and a desktop password
through cloud-init. Temporary build keys and password are removed.

## Build

Requires Linux with accessible KVM, Packer >= 1.10, QEMU, `qemu-img`, OpenSSL,
OpenSSH, `genisoimage` (or another Packer-supported ISO tool), and OVMF UEFI
firmware. Allow 8 GiB RAM for the build VM and at least 30 GiB free host storage.
The official ISO download is approximately 6 GiB.

```sh
scripts/build.sh
```

The wrapper creates temporary credentials under ignored `.tmp/`, installs the
QEMU plugin, and removes the credentials when it exits. Packer downloads and
checksum-verifies the pinned ISO. Output is `output/omarchy.qcow2`. A populated
output directory must be moved or removed before rebuilding.

Override variables by passing Packer flags to the wrapper:

```sh
scripts/build.sh -var 'disk_size_gb=60' -var 'output_dir=output-large'
```

OVMF defaults to Ubuntu/Debian's `/usr/share/OVMF/OVMF_CODE_4M.fd` and
`OVMF_VARS_4M.fd`; override `efi_firmware_code` and `efi_firmware_vars` on other
hosts. Boot the resulting image with UEFI and Secure Boot disabled. Each VM
needs its own writable copy of OVMF VARS. The image contains the fallback EFI
bootloader and does not require the build VM's firmware state.

## First boot

Attach a NoCloud seed disk labeled `cidata` containing `user-data` and
`meta-data`. Use a unique instance ID for each VM. For example:

```yaml
#cloud-config
users:
  - name: sherpa
    shell: /bin/bash
    lock_passwd: false
    hashed_passwd: '$6$REPLACE_WITH_YOUR_SHA512_PASSWORD_HASH'
    sudo: ALL=(ALL) ALL
    ssh_authorized_keys:
      - ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY
ssh_pwauth: false
```

Generate a desktop password hash with `openssl passwd -6`. Omit the password
fields for an SSH-only instance. Omarchy's user configuration already belongs
to `sherpa`; configure this existing user rather than creating a replacement.

```yaml
instance-id: sherpa-omarchy-001
local-hostname: sherpa-omarchy
```

Create the seed with `cloud-localds seed.iso user-data meta-data`, then attach
it alongside the qcow2 disk in your VM manager. Give desktop VMs a virtual
GPU with graphics acceleration appropriate to Hyprland.

## Validation

```sh
bash -n scripts/*.sh
packer fmt -check omarchy.pkr.hcl
packer validate -syntax-only omarchy.pkr.hcl
scripts/02-verify.sh output/omarchy.qcow2
```

The verifier boots a temporary overlay with fresh firmware and cloud-init
credentials, checks Omarchy and first-boot behavior over SSH, and removes the
overlay. It verifies boot and provisioning; desktop rendering requires a
graphical VM session.

Installer configuration follows the upstream [unattended installation
documentation](https://github.com/omacom/omarchy/blob/quattro/manual/51-unattended-installs.md)
and [ISO integration fixture](https://github.com/omacom/omarchy-iso/blob/quattro/test/integration.d/base-test.sh).
Cloud-init is supplied by [Arch Linux](https://archlinux.org/packages/extra/any/cloud-init/).
When updating the ISO, update its checksum and check the installer JSON schema
against the matching upstream release.
