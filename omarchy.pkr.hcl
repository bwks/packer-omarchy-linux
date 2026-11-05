packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key_file" {
  type    = string
  default = ".tmp/packer_key"
}

variable "build_password" {
  type      = string
  sensitive = true
  validation {
    condition     = can(regex("^[A-Za-z0-9]{16,}$", var.build_password))
    error_message = "Use a temporary build password of at least 16 alphanumeric characters."
  }
}

variable "build_password_hash" {
  type      = string
  sensitive = true
}

variable "iso_url" {
  type    = string
  default = "https://iso.omarchy.org/omarchy-4.5.0-x86.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:5d6288bc57f96f6231719830457582c846a2291985201c36a9a7d1216978b00f"
}

variable "output_dir" {
  type    = string
  default = "output"
}

variable "disk_size_gb" {
  type    = number
  default = 40
  validation {
    condition     = var.disk_size_gb >= 40 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "The disk must be at least 40 GiB, in whole GiB."
  }
}

variable "efi_firmware_code" {
  type    = string
  default = "/usr/share/OVMF/OVMF_CODE_4M.fd"
}

variable "efi_firmware_vars" {
  type    = string
  default = "/usr/share/OVMF/OVMF_VARS_4M.fd"
}

source "qemu" "omarchy" {
  iso_url           = var.iso_url
  iso_checksum      = var.iso_checksum
  output_directory  = var.output_dir
  vm_name           = "omarchy.qcow2"
  format            = "qcow2"
  disk_size         = "${var.disk_size_gb}G"
  disk_interface    = "virtio"
  accelerator       = "kvm"
  machine_type      = "q35"
  cpu_model         = "host"
  cpus              = 4
  memory            = 8192
  headless          = true
  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars
  # Empty disk falls through to the ISO; after installation boot from disk.
  qemuargs = [["-boot", "order=c,menu=off"]]

  cd_label = "cidata"
  cd_content = {
    "user_configuration.json" = templatefile("${path.root}/http/user-configuration.pkrtpl.hcl", {
      root_size_bytes = var.disk_size_gb * 1024 * 1024 * 1024 - 2148532224 - 1048576
    })
    "user_credentials.json" = templatefile("${path.root}/http/user-credentials.pkrtpl.hcl", {
      password_hash = var.build_password_hash
    })
    "user_encrypt_installation.txt" = "false\n"
    "authorized_keys"               = "${var.ssh_public_key}\n"
  }

  ssh_username           = "sherpa"
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = "45m"
  ssh_handshake_attempts = 100
  boot_wait              = "5s"
  shutdown_command       = "sudo -n bash -c 'rm -f /etc/sudoers.d/zz-packer-sherpa; systemctl poweroff'"
}

build {
  name    = "omarchy"
  sources = ["source.qemu.omarchy"]

  provisioner "shell" {
    execute_command = "printf '%s\\n' '${var.build_password}' | sudo -S -p '' bash '{{.Path}}'"
    script          = "scripts/install-cloud-init.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -n bash '{{.Path}}'"
    scripts         = ["scripts/00-zero-disk.sh", "scripts/01-cleanup.sh"]
  }

  post-processor "shell-local" {
    environment_vars = ["IMAGE_PATH=${var.output_dir}/omarchy.qcow2"]
    script           = "scripts/compress.sh"
  }
}
