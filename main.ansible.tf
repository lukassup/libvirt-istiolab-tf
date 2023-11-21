##
#   Ansible invetory setup
#

locals {
  ssh_opts = join(" ", [
    "-o StrictHostKeyChecking=no",
    "-o UserKnownHostsFile=/dev/null",
    # use ProxyJump to SSH via libvirt host
    !var.libvirt_local ? "-J ${var.libvirt_host}" : ""
  ])
  # group hosts by function/extra_role for Ansible inventory
  hosts_by_role = merge(
    { for hostname, params in local.host_params: params.function => hostname... },
    { for hostname, params in local.host_params: params.extra_role => hostname... },
  )
  ansible_hostvars = { for name, domain in libvirt_domain.domain :
    name => {
      ansible_host = domain.network_interface[0].addresses[0]
      ansible_user = var.user
      become_user = var.user
    }
  }
}

resource "local_file" "ansible_inventory" {
  content  = templatefile("${path.module}/inventory.tftpl", {
    ssh_opts = local.ssh_opts
    roles = local.hosts_by_role
    ansible_hostvars = local.ansible_hostvars
  })
  filename = "${path.module}/ansible/topology-${var.topology_id}.inventory"
  file_permission = "0640"
  directory_permission = "0750"
}
