terraform {
  required_version = ">= 1.6"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.0"
    }
  }
}

variable "topology_file" {
  type    = string
  default = "topology.dot.json"
}

variable "topology_id" {
  type    = number
  default = 1
}

variable "libvirt_local" {
  type    = bool
  default = true
}

variable "libvirt_host" {
  type    = string
  default = null
}

variable "image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}

variable "user" {
  type    = string
  default = "debian"
}

variable "topology_network_prefix" {
  type    = string
  default = "172.31.0.0/16"
}

locals {
  network_cidr = cidrsubnet(var.topology_network_prefix, 8, var.topology_id)
  tunnel_cidr  = cidrsubnet("127.1.0.0/16", 8, var.topology_id)
}

variable "console" {
  type    = bool
  default = false
}

provider "libvirt" {
  uri = var.libvirt_local ? "qemu:///system" : "qemu+ssh://${var.libvirt_host}/system"
}

resource "libvirt_network" "mgmt_network" {
  name      = format("%02d-mgmt-network", var.topology_id)
  bridge    = "virbr${100 + var.topology_id}"
  mode      = "nat"
  addresses = [local.network_cidr]
  domain    = "kvm.local"
  autostart = true
  dhcp {
    enabled = true
  }
  dns {
    enabled    = true
    local_only = false
  }
}

resource "libvirt_volume" "base" {
  name   = "debian12-latest.qcow2"
  source = var.image_url
}

resource "libvirt_volume" "vol" {
  for_each       = { for host, i in local.hosts : host => i + 1 }
  name           = format("%02d-%s.qcow2", var.topology_id, each.key)
  base_volume_id = libvirt_volume.base.id
  size           = local.host_params[each.key].disk
}

resource "libvirt_cloudinit_disk" "cloud_init" {
  for_each  = { for host, i in local.hosts : host => i + 1 }
  name      = format("%02d-%s-cloudinit.iso", var.topology_id, each.key)
  meta_data = templatefile("${path.module}/cloud-init/meta-data.yml", {})
  user_data = templatefile("${path.module}/cloud-init/user-data.yml", {
    user               = var.user
    ssh_authorized_key = trimspace(file(pathexpand("~/.ssh/id_rsa.pub")))
    function           = local.host_params[each.key].function
    mgmt_mac           = format("52:54:00:%02x:00:%02x", var.topology_id, each.value)
    links              = lookup(local.links, each.key, [])
  })
  network_config = templatefile("${path.module}/cloud-init/network-config.yml", {
    # NOTE: network-config requires mac to be lowercase :-(
    mgmt_mac = format("52:54:00:%02x:00:%02x", var.topology_id, each.value)
    function = local.host_params[each.key].function
    eth1     = local.host_params[each.key].function == "host"
  })
}

resource "libvirt_domain" "domain" {
  for_each  = { for host, i in local.hosts : host => i + 1 }
  name      = format("%02d-%s", var.topology_id, each.key)
  vcpu      = local.host_params[each.key].cpu
  memory    = local.host_params[each.key].memory
  autostart = true
  cloudinit = libvirt_cloudinit_disk.cloud_init[each.key].id
  machine   = "q35"

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.vol[each.key].id
  }

  network_interface {
    network_id = libvirt_network.mgmt_network.id
    hostname   = each.key
    # NOTE: first subnet IP is reserved for libvirt network bridge
    addresses = [cidrhost(local.network_cidr, each.value + 1)]
    # NOTE: MAC address must start from 01
    mac            = format("52:54:00:%02X:00:%02X", var.topology_id, each.value)
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
  graphics {
    type        = var.console ? "spice" : null
    listen_type = var.console ? "address" : null
  }
  video {
    type = var.console ? "qxl" : null
  }

  xml {
    xslt = templatefile("${path.module}/domain.xslt.tftpl", {
      tunnel_cidr = local.tunnel_cidr
      links       = lookup(local.links, each.key, [])
    })
  }

  lifecycle {
    # ignore changes done in XSLT
    ignore_changes = [firmware, nvram, network_interface, xml]
  }
}

locals {
  ssh_cmd = format("ssh%s", !var.libvirt_local ? " -J ${var.libvirt_host}" : "")
}

output "ip_addrs" {
  value = [for d in libvirt_domain.domain : d.network_interface[0].addresses[0]]
}

output "ssh_cmd" {
  value = { for name, domain in libvirt_domain.domain :
    name => format("%s %s@%s", local.ssh_cmd, var.user, domain.network_interface[0].addresses[0])
  }
}
