# Kubernetes - enable IPVS

```sh
kubectl edit configmap -n kube-system kube-proxy
```

```yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
ipvs:
  strictARP: true
```

```sh
kubectl delete pod -n kube-system -l k8s-app=kube-proxy
```

# Calico - install

- install [`calicoctl`](https://github.com/projectcalico/calico/releases/tag/v3.26.3) on Kubernetes control plane nodes
- install [Calico manifest](https://github.com/projectcalico/calico/blob/v3.26.3/manifests/calico.yaml) using `kubectl apply -f calico.yaml`

# Calico - fix for incorrect interface autodetect

```sh
kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD=kubernetes-internal-ip
```

# Calico - disable IPIP, VXLAN, NAT globally and for default pool

```sh
kubectl set env daemonset/calico-node -n kube-system CALICO_IPV4POOL_IPIP=Never
kubectl set env daemonset/calico-node -n kube-system CALICO_IPV4POOL_VXLAN=Never
kubectl set env daemonset/calico-node -n kube-system CALICO_IPV4POOL_NAT_OUTGOING=false

kubectl wait pods -n kube-system -l k8s-app=calico-node --for condition=Ready --timeout=90s

calicoctl patch pool default-ipv4-ippool --patch='{"spec":{"ipipMode":"Never"}}'
calicoctl patch pool default-ipv4-ippool --patch='{"spec":{"vxlanMode":"Never"}}'
calicoctl patch pool default-ipv4-ippool --patch='{"spec":{"natOutgoing":false}}'
```

# Calico - configure BGP peers for ToR switch

```sh
calicoctl apply -f - <<EOF
---
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: rack-10-0-1-tor
spec:
  asNumber: 64513
  nodeSelector: rack == 'rack-10-0-1'
  peerIP: 10.0.1.254
---
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: rack-10-0-2-tor
spec:
  asNumber: 64514
  nodeSelector: rack == 'rack-10-0-2'
  peerIP: 10.0.2.254
---
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: rack-10-0-3-tor
spec:
  asNumber: 64515
  nodeSelector: rack == 'rack-10-0-3'
  peerIP: 10.0.3.254
EOF
```

# Calico - add rack labels for nodes

```sh
kubectl label node kube-ctrl01 rack=rack-10-0-1
kubectl label node kube-node01 rack=rack-10-0-1

kubectl label node kube-ctrl02 rack=rack-10-0-2
kubectl label node kube-node02 rack=rack-10-0-2

kubectl label node kube-ctrl03 rack=rack-10-0-3
kubectl label node kube-node03 rack=rack-10-0-3
```

# Calico - set node BGP ASN

```sh
calicoctl patch node kube-ctrl01 --patch='{"spec":{"bgp":{"asNumber":64513}}}'
calicoctl patch node kube-node01 --patch='{"spec":{"bgp":{"asNumber":64513}}}'

calicoctl patch node kube-ctrl02 --patch='{"spec":{"bgp":{"asNumber":64514}}}'
calicoctl patch node kube-node02 --patch='{"spec":{"bgp":{"asNumber":64514}}}'

calicoctl patch node kube-ctrl03 --patch='{"spec":{"bgp":{"asNumber":64515}}}'
calicoctl patch node kube-node03 --patch='{"spec":{"bgp":{"asNumber":64515}}}'
```

# Calico - cluster-wide BGP configuration

```sh
calicoctl apply -f - <<EOF
---
apiVersion: projectcalico.org/v3
kind: BGPConfiguration
metadata:
  name: default
spec:
  nodeToNodeMeshEnabled: false
  logSeverityScreen: Info
  bindMode: NodeIP
  serviceClusterIPs:
    - cidr: 10.1.1.0/24
  serviceExternalIPs:
    - cidr: 10.2.0.0/24
    - cidr: 10.10.10.10/32
EOF
```

# Calico - verify successful BGP peering with ToR switch


```
# calicoctl node status
Calico process is running.

IPv4 BGP status
+--------------+---------------+-------+----------+-------------+
| PEER ADDRESS |   PEER TYPE   | STATE |  SINCE   |    INFO     |
+--------------+---------------+-------+----------+-------------+
| 10.0.1.254   | node specific | up    | 09:20:33 | Established |
+--------------+---------------+-------+----------+-------------+
```

# FRR - BGP sessions should now be established

```
leaf01# show bgp vrf vrf-main ipv4 unicast summary 
BGP router identifier 10.0.0.1, local AS number 64513 vrf-id 7
BGP table version 18
RIB entries 29, using 5568 bytes of memory
Peers 4, using 2896 KiB of memory
Peer groups 2, using 128 bytes of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
*10.0.1.1       4      64513       211       218        0    0    0 00:10:22            2       12 N/A
*10.0.1.2       4      64513       209       216        0    0    0 00:10:17            2       12 N/A
spine01(swp1)   4      64512      1512      1513        0    0    0 01:14:51           10       15 N/A
spine02(swp2)   4      64512      1512      1514        0    0    0 01:14:51           10       15 N/A

Total number of neighbors 4
* - dynamic neighbor
2 dynamic neighbor(s), limit 100


leaf01# show bgp vrf vrf-main ipv4 unicast neighbors 10.0.1.1 routes      
BGP table version is 18, local router ID is 10.0.0.1, vrf id 7
Default local pref 100, local AS 64513
Status codes:  s suppressed, d damped, h history, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found

   Network          Next Hop            Metric LocPrf Weight Path
*>i10.1.1.0/24      10.0.1.1                      100      0 i
*>i10.2.107.192/26  10.0.1.1                      100      0 i

Displayed  2 routes and 26 total paths

leaf01# show bgp vrf vrf-main ipv4 unicast neighbors 10.0.1.2 routes 
BGP table version is 18, local router ID is 10.0.0.1, vrf id 7
Default local pref 100, local AS 64513
Status codes:  s suppressed, d damped, h history, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found

   Network          Next Hop            Metric LocPrf Weight Path
*=i10.1.1.0/24      10.0.1.2                      100      0 i
*>i10.2.0.128/26    10.0.1.2                      100      0 i

Displayed  2 routes and 26 total paths
```

# Kubectl - test deployment and service

```
# kubectl create deployment httpbin --image=kong/httpbin --replicas=3 --port=80
# kubectl expose deploy/httpbin --target-port=80 --port=80

# kubectl get pod -l=app=httpbin -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE          ...
httpbin-84f9b5cbd7-77mcl   1/1     Running   0          52s   10.2.0.132   kube-node01   ...
httpbin-84f9b5cbd7-f87mh   1/1     Running   0          54s   10.2.161.1   kube-node03   ...
httpbin-84f9b5cbd7-q9x7p   1/1     Running   0          56s   10.2.238.1   kube-node02   ...

# kubectl get svc -l=app=httpbin
NAME    TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
kuard   ClusterIP   10.1.1.101   <none>        8080/TCP   22m


## test pod icmp ping
# for ip in $(kubectl get pod -l=app=httpbin -o jsonpath='{..status.podIP}'); do ping -c1 $ip; done

## test pod tcp connectivity
# for ip in $(kubectl get pod -l=app=httpbin -o jsonpath='{..status.podIP}'); do nc -zv $ip 80; done

## test pod http
# POD_URLS=$(kubectl get pod -l=app=httpbin -o=jsonpath='{ range .items[*] }http://{ .status.podIP }:80{"\n"}{ end }')
# for url in ${POD_URLS[@]}; do curl -sSLD/dev/stdout -o/dev/null "$url"; done

## test svc icmp ping
# SVC_IP=$(kubectl get svc/httpbin -o=jsonpath='{.spec.clusterIP}')
# ping -c1 $SVC_IP

## test svc tcp connectivity
# SVC_PORT=$(kubectl get svc/httpbin -o=jsonpath='{.spec.ports[0].targetPort}')
# nc -zv $SVC_IP $SVC_PORT

## test svc http
# SVC_URL=http://$SVC_IP:$SVC_PORT
# curl -sSLD/dev/stdout -o/dev/null "$SVC_URL"
```
