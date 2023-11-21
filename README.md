# libvirt-network-topology-tf

Some shell Terraform scipts to create a basic 2 leaf 2 spine topology from Debian Cloud machines.

```mermaid
graph TD;
    internet --> eth0;
    eth0 --> virbrN;
    subgraph vrf-main
      leaf01 & leaf02 & leaf03 -->|swpN| spine01 & spine02;
      kube-ctrl01 --> leaf01;
      kube-node01 --> leaf01;
      istio-ingress01 --> leaf01;
      kube-ctrl02 --> leaf02;
      kube-node02 --> leaf02;
      istio-ingress02 --> leaf02;
      kube-ctrl03 --> leaf03;
      kube-node03 --> leaf03;
      istio-ingress03 --> leaf03;
    end
    subgraph mgmt-net
      oob-mgmt-server & leaf01 & leaf02 & leaf03 & spine01 & spine02 -->|eth0| virbrN;
    end
```

### USAGE

1. Use `make` to create virtual machines
    ```command
    make create
    ```
1. Use `make` to converge Ansible configuration
    ```command
    make converge
    ```
1. Use `make` to destroy virtual machines
    ```command
    make destroy
    ```

#### Remote libvirt

Set `libvirt_local=false` and `libvirt_host` variables to 

```sh
cat > .auto.tfvars <<EOF
libvirt_local=false
libvirt_host="user@host.example.com"
EOF
```

> NOTE: macOS needs `cdrtools` for cloudinit disk: `brew install cdrtools`

