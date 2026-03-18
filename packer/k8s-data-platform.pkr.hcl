packer {
  required_version = ">= 1.10.0"

  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = ">= 1.1.0"
    }
  }
}

variable "iso_url" { type = string }
variable "iso_checksum" { type = string }
variable "vm_name" { type = string }
variable "cpus" { type = number }
variable "memory" { type = number }
variable "disk_size" { type = number }
variable "ssh_username" { type = string }
variable "ssh_password" { type = string }
variable "output_directory" { type = string }
variable "http_directory" { type = string }
variable "headless" { type = bool }
variable "ovftool_path_windows" {
  type    = string
  default = ""
}
variable "vmware_workstation_path" {
  type    = string
  default = ""
}

source "virtualbox-iso" "k8s_data_platform" {
  vm_name          = var.vm_name
  guest_os_type    = "Ubuntu_64"
  cpus             = var.cpus
  memory           = var.memory
  disk_size        = var.disk_size
  headless         = var.headless
  output_directory = var.output_directory

  iso_url        = var.iso_url
  iso_checksum   = var.iso_checksum
  http_directory = var.http_directory

  communicator     = "ssh"
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "60m"
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"

  boot_wait = "25s"
  boot_command = [
    "<wait><wait><wait><esc><wait>",
    "e<wait>",
    "<down><down><down><end><wait>",
    " autoinstall ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<wait>",
    "<f10><wait>"
  ]
}

build {
  sources = ["source.virtualbox-iso.k8s_data_platform"]

  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    inline = [
      "echo 'Waiting for cloud-init to finish'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 5; done",
      "install -d -m 0755 /home/${var.ssh_username}/k8s-data-platform-src",
      "chown -R ${var.ssh_username}:${var.ssh_username} /home/${var.ssh_username}/k8s-data-platform-src"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../ansible"
    destination = "/home/${var.ssh_username}/k8s-data-platform-src"
  }

  provisioner "file" {
    source      = "${path.root}/../apps"
    destination = "/home/${var.ssh_username}/k8s-data-platform-src"
  }

  provisioner "file" {
    source      = "${path.root}/../infra"
    destination = "/home/${var.ssh_username}/k8s-data-platform-src"
  }

  provisioner "file" {
    source      = "${path.root}/../scripts"
    destination = "/home/${var.ssh_username}/k8s-data-platform-src"
  }

  provisioner "file" {
    source      = "${path.root}/../docs"
    destination = "/home/${var.ssh_username}/k8s-data-platform-src"
  }

  provisioner "file" {
    source      = "${path.root}/../README.md"
    destination = "/home/${var.ssh_username}/k8s-data-platform-src/README.md"
  }

  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    expect_disconnect = true
    valid_exit_codes  = [0, 2300218]
    inline = [
      "apt-get update",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y ansible || true"
    ]
  }

  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    inline = [
      "set -e",
      "ansible-playbook -i 'localhost,' -c local /home/${var.ssh_username}/k8s-data-platform-src/ansible/playbook.yml",
      "rm -rf /home/${var.ssh_username}/k8s-data-platform-src"
    ]
  }
}
