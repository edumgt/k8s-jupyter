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
  ssh_timeout      = "30m"
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"

  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz autoinstall ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---<enter>",
    "initrd /casper/initrd<enter>",
    "boot<enter>"
  ]
}

build {
  sources = ["source.virtualbox-iso.k8s_data_platform"]

  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 5; done"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../ansible"
    destination = "/tmp/k8s-data-platform-src/"
  }

  provisioner "file" {
    source      = "${path.root}/../apps"
    destination = "/tmp/k8s-data-platform-src/"
  }

  provisioner "file" {
    source      = "${path.root}/../infra"
    destination = "/tmp/k8s-data-platform-src/"
  }

  provisioner "file" {
    source      = "${path.root}/../scripts"
    destination = "/tmp/k8s-data-platform-src/"
  }

  provisioner "file" {
    source      = "${path.root}/../docs"
    destination = "/tmp/k8s-data-platform-src/"
  }

  provisioner "file" {
    source      = "${path.root}/../README.md"
    destination = "/tmp/k8s-data-platform-src/README.md"
  }

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible",
      "sudo ansible-playbook -i 'localhost,' -c local /tmp/k8s-data-platform-src/ansible/playbook.yml",
      "sudo rm -rf /tmp/k8s-data-platform-src"
    ]
  }
}
