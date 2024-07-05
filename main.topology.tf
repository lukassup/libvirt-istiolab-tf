##
#  topology.dot file parsing
#

data "local_file" "topology" {
  filename = "${path.module}/${var.topology_file}"
}

locals {
  # topology nodes
  topology_objects = lookup(jsondecode(data.local_file.topology.content), "objects", [])
  hosts            = { for o in local.topology_objects : (o.name) => o._gvid }
  host_names       = { for o in local.topology_objects : (o._gvid) => o.name }
  host_params = { for o in local.topology_objects :
    (o.name) => {
      id         = o._gvid
      cpu        = lookup(o, "cpu", null) != null ? tonumber(o.cpu) : null
      memory     = lookup(o, "memory", null) != null ? tonumber(o.memory) : null
      disk       = lookup(o, "disk", null) != null ? tonumber(o.disk) * pow(2, 30) : null
      function   = lookup(o, "function", "leaf")
      extra_role = lookup(o, "extra_role", "_")
    }
  }

  # topology links
  topology_edges = lookup(jsondecode(data.local_file.topology.content), "edges", [])
  # forward links
  links_forward = { for e in local.topology_edges :
    (local.host_names[e.head]) => {
      link_id = e._gvid
      src_id  = e.head
      dst_id  = e.tail
      # FIXME: currently supports max 127 links per topology, possible solution
      #   octet5 = (link_id * 2)  / 255 # can overflow
      #   octet6 = (link_id * 2) // 255
      src_mac  = format("52:54:00:%02x:01:%02x", var.topology_id, e._gvid * 2) # even
      src_port = e.headport
      dst_port = e.tailport
      dst_host = local.host_names[e.tail]
    }...
  }
  # reverse links
  links_reverse = { for e in local.topology_edges :
    (local.host_names[e.tail]) => {
      link_id = e._gvid
      src_id  = e.tail
      dst_id  = e.head
      # FIXME: currently supports max 127 links per topology, possible solution
      #   octet5 = (link_id * 2 + 1)  / 255  # can overflow
      #   octet6 = (link_id * 2 + 1) // 255
      src_mac  = format("52:54:00:%02x:01:%02x", var.topology_id, e._gvid * 2 + 1) # odd
      src_port = e.tailport
      dst_port = e.headport
      dst_host = local.host_names[e.head]
    }...
  }
  # merge forward and reverse links
  links = { for host in setunion(keys(local.links_forward), keys(local.links_reverse)) :
    host => concat(lookup(local.links_forward, host, []), lookup(local.links_reverse, host, []))
  }
}
