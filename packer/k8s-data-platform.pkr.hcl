packer {
  required_version = ">= 1.10.0"
  required_plugins {
    vmware = {
      source  = "github.com/hashicorp/vmware"
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
variable "vmware_workstation_path" { type = string }
variable "ovftool_path_windows" { type = string }
variable "output_directory" { type = string }
variable "http_directory" { type = string }
variable "headless" { type = bool }

source "vmware-iso" "k8s_data_platform" {
  vm_name          = var.vm_name
  guest_os_type    = "ubuntu-64"
  cpus             = var.cpus
  memory           = var.memory
  disk_size        = var.disk_size
  headless         = var.headless
  network_adapter_type = "vmxnet3"
  output_directory = var.output_directory
  vmx_data = {
    "displayName" = var.vm_name
    "numvcpus"    = var.cpus
    "memsize"     = var.memory
  }

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
  sources = ["source.vmware-iso.k8s_data_platform"]

  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 5; done"
    ]
  }

  
}
