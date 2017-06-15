# Setup a Kubernetes Cluster
This tutorial refers to a cluster of nodes (virtual, physical or a mix of both) running CentOS 7.3 Operating System. We'll set Kubernetes components as system processes managed by systemd.

   * [Requirements](#requirements)
   * [Configure Master](#configure-masters)
   * [Configure Workers](#configure-workers)
   * [Test the cluster](#test-the-cluster)
   * [Configure DNS service](#configure-dns-service)
   * [Configure GUI dashboard](#configure-gui-dashboard)
   
## Requirements
Our initial cluster will be made of 1 Master node and 3 Workers nodes. All machines can be virtual or physical or a mix of both. Minimum hardware requirements are: 2 vCPUs, 2GB of RAM, 16GB HDD for OS and 16GB HDD for Docker volumes. All machines will be installed with Linux CentOS 7.3. Firewall and Selinux will be disabled. An NTP server is installed and running on all machines. Docker is installed with a Device Mapper on a separate HDD. Internet access.

Here the hostnames:

    kube00 10.10.10.80 (master)
    kube01 10.10.10.81 (worker)
    kube02 10.10.10.82 (worker)
    kube03 10.10.10.82 (worker)

Make sure to enable DNS resolution for the above hostnames or set the ``/etc/hosts`` file on all the machines.

For networking we are going to use **Flannel**, a simple overlay networking daemon for kubernetes. There are many networking solutions available out there. Flannel is very simple to setup and use. Flannel gives a dedicated subnet to each host for use with container runtimes. Details about Flannel are [here](https://github.com/coreos/flannel).

Make sure IP forwarding kernel option is enabled

    cat /etc/sysctl.conf
      net.ipv4.ip_forward = 1
    sysctl -p /etc/sysctl.conf

Create default kubernetes reposistory on all the nodes:

    [virt7-docker-common-release]
    name=virt-docker-common-release
    baseurl=http://cbs.centos.org/repos/virt7-docker-common-release/x86_64/os/
    gpgcheck=0

## Configure Masters
On the Master, first install etcd, kubernetes and flanneld

    yum -y install --enablerepo=virt7-docker-common-release kubernetes etcd flannel

### Configure etcd
Before launching and enabling the etcd service you need to define its configuration in ``/etc/etcd/etcd.conf``. The file contains several lines. You need to make sure the following are uncommented and setted as shown below.

    # [member]
    ETCD_NAME=default
    ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
    ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
    # [cluster]
    ETCD_ADVERTISE_CLIENT_URLS="http://0.0.0.0:2379"
    # [logging]
    ETCD_DEBUG="true"

Start and enable the service

    systemctl start etcd
    systemctl enable etcd
    systemctl status etcd

### Configure common Kubernetes
To configure common options, edit the ``/etc/kubernetes/config`` configuration file

    KUBE_LOGTOSTDERR="--logtostderr=true"
    KUBE_LOG_LEVEL="--v=0"
    # Should this cluster be allowed to run privileged docker containers
    KUBE_ALLOW_PRIV="--allow-privileged=true"
    # How the controller-manager, scheduler, and proxy find the apiserver
    KUBE_MASTER="--master=http://kube00:8080"
    # Comma separated list of nodes running etcd cluster
    KUBE_ETCD_SERVERS="--etcd_servers=http://kube00:2379"

Kubernetes uses certificates to authenticate API request. We need to generate certificates that can be used for authentication. Kubernetes provides ready made scripts for generating these certificates which can be found [here](https://github.com/kalise/Kubernetes-Lab-Tutorial/tree/master/utils/ca-cert.sh).

Download this script, set right permissions and exec as follow

    MASTER_IP=10.10.10.80
    KUBE_SVC_IP=10.254.0.1
    bash ca-cert.sh "${MASTER_IP}" "IP:${MASTER_IP},IP:${KUBE_SVC_IP},DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster.local"

This script will create certificates in ``/srv/kubernetes/`` directory

    ll /srv/kubernetes/
    total 28
    -rw-rw---- 1 root kube 1216 Apr 19 18:36 ca.crt
    -rw------- 1 root root 4466 Apr 19 18:36 kubecfg.crt
    -rw------- 1 root root 1704 Apr 19 18:36 kubecfg.key
    -rw-rw---- 1 root kube 4868 Apr 19 18:36 server.cert
    -rw-rw---- 1 root kube 1704 Apr 19 18:36 server.key

### Configure API server
To configure the API server, edit the ``/etc/kubernetes/apiserver`` configuration file

    # The address on the local server to listen to.
    KUBE_API_ADDRESS="--address=0.0.0.0"
    # The port on the local server to listen on.
    KUBE_API_PORT="--port=8080"
    # Port minions listen on
    KUBELET_PORT="--kubelet-port=10250"
    # Comma separated list of nodes in the etcd cluster
    KUBE_ETCD_SERVERS="--etcd-servers=http://kube00:2379"
    # Address range to use for services
    KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range=10.254.0.0/16"
    # default admission control policies
    KUBE_ADMISSION_CONTROL="--admission-control=NamespaceLifecycle,NamespaceExists,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota"
    # Add your own!
    KUBE_API_ARGS="--client-ca-file=/srv/kubernetes/ca.crt --tls-cert-file=/srv/kubernetes/server.cert --tls-private-key-file=/srv/kubernetes/server.key"

Start and enable the service

    systemctl start kube-apiserver
    systemctl enable kube-apiserver
    systemctl status kube-apiserver

### Configure controller manager
To configure the kubernetes controller manager, edit the ``/etc/kubernetes/controller-manager`` configuration file

    # defaults from config and apiserver should be adequate
    # Add your own!
    KUBE_CONTROLLER_MANAGER_ARGS="--root-ca-file=/srv/kubernetes/ca.crt --service-account-private-key-file=/srv/kubernetes/server.key"

Start and enable the service

    systemctl start kube-controller-manager
    systemctl enable kube-controller-manager
    systemctl status kube-controller-manager
    
### Configure scheduler
Usually, there are no needs to change default scheduler ``/etc/kubernetes/scheduler`` configuration file. For advanced options, please refer to the official documentation.

Start and enable the service

    systemctl start kube-scheduler
    systemctl enable kube-scheduler
    systemctl status kube-scheduler
    
### Configure Flannel
Before moving away from the master we will create a configuration key in etcd defining the flannel network which will be used by the nodes.

Configure the flanneld service by editing the ``/etc/sysconfig/flanneld`` configuration file

    # Flanneld configuration options
    # etcd url location.  Point this to the server where etcd runs
    FLANNEL_ETCD_ENDPOINTS="http://kube00:2379"
    # etcd config key.  This is the configuration key that flannel queries
    # For address range assignment
    FLANNEL_ETCD_PREFIX="/kube-centos/network"
    # Any additional options that you want to pass
    FLANNEL_OPTIONS=""

In etcd, create a flannel network 

    etcdctl mkdir /kube-centos/network
    etcdctl mk /kube-centos/network/config "{ \"Network\": \"172.30.0.0/16\", \"SubnetLen\": 24, \"Backend\": { \"Type\": \"vxlan\" } }"

Start and enable the flanneld service

    systemctl start flanneld
    systemctl enable flanneld
    systemctl status flanneld

To prevent docker main service starts before flanneld and then being not able to use flannel network, update the docker startup  ``/usr/lib/systemd/system/docker.service`` configuration file

    [Unit]
    ...
    After=flanneld.service
    Requires=flanneld.service
    ...

Restart the docker service

    systemctl daemon-reload
    systemctl restart docker
    systemctl status docker

## Configure Workers
On all the worker nodes, install the Kubernetes components and flanneld

    yum -y install --enablerepo=virt7-docker-common-release kubernetes flannel

To configure common options, edit the ``/etc/kubernetes/config`` configuration file

    KUBE_LOGTOSTDERR="--logtostderr=true"
    KUBE_LOG_LEVEL="--v=0"
    # Should this cluster be allowed to run privileged docker containers
    KUBE_ALLOW_PRIV="--allow-privileged=true"
    # How the controller-manager, scheduler, and proxy find the apiserver
    KUBE_MASTER="--master=http://kube00:8080"
    # Comma separated list of nodes running etcd cluster
    #KUBE_ETCD_SERVERS="--etcd_servers=http://127.0.0.1:2379"

### Configure kubelet
To configure the kubelet component, edit the ``/etc/kubernetes/kubelet`` configuration file

    # The address for the info server to serve on
    KUBELET_ADDRESS="--address=0.0.0.0"
    # The port for the info server to serve on
    KUBELET_PORT="--port=10250"
    # You may leave this blank to use the actual hostname
    KUBELET_HOSTNAME="--hostname-override=<kube-node-name>"
    # location of the api-server
    KUBELET_API_SERVER="--api-servers=http://kube00:8080"
    # pod infrastructure container
    KUBELET_POD_INFRA_CONTAINER="--pod-infra-container-image=registry.access.redhat.com/rhel7/pod-infrastructure:latest"
    # Add your own!
    KUBELET_ARGS="--cluster-dns=10.254.3.100 --cluster-domain=cluster.local"

The cluster DNS parameter above refers to the DNS internal service used by Kubernetes for service discovery. We're going to configure it below.

Start and enable the kubelet service

    systemctl start kubelet
    systemctl enable kubelet
    systemctl status kubelet

### Configure proxy
Usually, there are no needs to change default proxy ``/etc/kubernetes/proxy`` configuration file. For advanced options, please refer to the official documentation.

Start and enable the service

    systemctl start kube-proxy
    systemctl enable kube-proxy
    systemctl status kube-proxy

### Configure Flannel
Configure flannel to overlay network in /etc/sysconfig/flanneld 

    # Flanneld configuration options
    # etcd url location.  Point this to the server where etcd runs
    FLANNEL_ETCD_ENDPOINTS="http://kube00:2379"
    # etcd config key.  This is the configuration key that flannel queries
    # For address range assignment
    FLANNEL_ETCD_PREFIX="/kube-centos/network"
    # Any additional options that you want to pass
    #FLANNEL_OPTIONS=""

Start and enable the flanneld service

    systemctl start flanneld
    systemctl enable flanneld
    systemctl status flanneld

To prevent docker main service starts before flanneld and then being not able to use flannel network, update the docker startup  ``/usr/lib/systemd/system/docker.service`` configuration file

    [Unit]
    ...
    After=flanneld.service
    Requires=flanneld.service
    ...

Restart the docker service

    systemctl daemon-reload
    systemctl restart docker
    systemctl status docker


## Test the cluster
The cluster should be now running. Check to make sure the cluster can see the node, by logging to the master

    kubectl get nodes
    NAME      STATUS    AGE
    kube01   Ready     2d
    kube02   Ready     2d
    kube03   Ready     2d

Kubernetes cluster stores all of its internal state in etcd. The idea is, that you should interact with Kubernetes only via its API provided by API service. API service abstracts away all the Kubernetes cluster state manipulating by reading from and writing into the etcd cluster. Let’s explore what’s stored in the etcd cluster after fresh installation:

    [root@kube00 ~]# etcdctl ls
    /kube-centos
    /registry

The etcd has the /registry area where stores all info related to the cluster. The /kube-centos area contains the flannel network configuration.

Let's see the cluster info stored in etcd

    [root@kube00 ~]# etcdctl ls /registry --recursive
    /registry/deployments
    /registry/deployments/default
    /registry/deployments/kube-system
    /registry/ranges
    /registry/ranges/serviceips
    /registry/ranges/servicenodeports
    /registry/secrets
    /registry/secrets/default
    /registry/secrets/default/default-token-92z22
    /registry/secrets/kube-system
    /registry/secrets/kube-system/default-token-sj7t3
    /registry/secrets/demo
    ...

For example, get detailed info about a worker node

    [root@kubem00 ~]# etcdctl ls /registry/minions
    /registry/minions/kube01
    /registry/minions/kube02
    /registry/minions/kube03
    
    [root@kubem00 ~]# etcdctl get /registry/minions/kube01 | jq .

```json
    {
      "kind": "Node",
      "apiVersion": "v1",
      "metadata": {
        "name": "kube01",
        "selfLink": "/api/v1/nodeskube01",
        "uid": "e4ad4619-17d6-11e7-acd7-000c29f8a512",
        "creationTimestamp": "2017-04-02T19:02:18Z",
        "labels": {
          "beta.kubernetes.io/arch": "amd64",
          "beta.kubernetes.io/os": "linux",
          "kubernetes.io/hostname": "kube01"
        },
        "annotations": {
          "volumes.kubernetes.io/controller-managed-attach-detach": "true"
        }
      },
      "spec": {
        "externalID": "kube01"
      },
      "status": {
        "capacity": {
          "alpha.kubernetes.io/nvidia-gpu": "0",
          "cpu": "1",
          "memory": "1884128Ki",
          "pods": "110"
        },
        "allocatable": {
          "alpha.kubernetes.io/nvidia-gpu": "0",
          "cpu": "1",
          "memory": "1884128Ki",
          "pods": "110"
        },
        "nodeInfo": {
          "machineID": "3061393c3cc943959069e4b3dd4d1276",
          "systemUUID": "564DBD0F-7CC4-E8CD-3882-0DDB6D9AB26E",
          "bootID": "3f286a35-3ae9-4e41-a9f8-4beb6f42477e",
          "kernelVersion": "3.10.0-514.10.2.el7.x86_64",
          "osImage": "CentOS Linux 7 (Core)",
          "containerRuntimeVersion": "docker://1.12.6",
          "kubeletVersion": "v1.5.2",
          "kubeProxyVersion": "v1.5.2",
          "operatingSystem": "linux",
          "architecture": "amd64"
        }
      }
    }
```

## Configure DNS service
To enable service name discovery in our Kubernetes cluster, we need to configure an embedded DNS service. To do so, we need to deploy DNS pod and service having configured kubelet to resolve all DNS queries from this local DNS service.

Login to the master node and download the DNS template ``kubedns-template.yaml`` from [here](https://github.com/kalise/Kubernetes-Lab-Tutorial/blob/master/examples/kubedns-template.yaml)

This template defines a Replica Controller and a DNS service. The controller defines three containers running on the same pod: a DNS server, a dnsmaq for caching and healthz for liveness probe:
```yaml
...
    spec:
      containers:
      - name: kubedns
        image: gcr.io/google_containers/kubedns-amd64:1.8
...
      - name: dnsmasq
        image: gcr.io/google_containers/kube-dnsmasq-amd64:1.4
...
      - name: healthz
        image: gcr.io/google_containers/exechealthz-amd64:1.2
```

Here the DNS service definition
```yaml
...
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "KubeDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.254.3.100
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
```

Note: make sure you have updated in the above file the correct cluster IP ``10.254.3.100`` as we specified in kubelet configuration file for DNS service ``--cluster-dns=10.254.3.100`` option.


Create the DNS for service discovery

    [root@kube00 ~]# kubectl create -f kubedns-template.yaml
    replicationcontroller "kube-dns-v20" created
    service "kube-dns" created

and check if it works in the dedicated namespace

    [root@kube00 ~]# kubectl get all -n kube-system
    NAME              DESIRED   CURRENT   READY     AGE
    rc/kube-dns-v20   1         1         1         22m
    NAME           CLUSTER-IP     EXTERNAL-IP   PORT(S)         AGE
    svc/kube-dns   10.254.3.100   <none>        53/UDP,53/TCP   22m
    NAME                    READY     STATUS    RESTARTS   AGE
    po/kube-dns-v20-3xk4v   3/3       Running   0          22m

To test if it works, create a file named ``busybox.yaml`` with the following contents:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: busybox
  namespace: default
spec:
  containers:
  - image: busybox
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
    name: busybox
  restartPolicy: Always
```

Then create a pod using this file

    kubectl create -f busybox.yaml
    
wait for pod is running and validate that DNS is working by resolving the kubernetes service

    kubectl exec -ti busybox -- nslookup kubernetes    
    Server:    10.254.3.100
    Address 1: 10.254.3.100 kube-dns.kube-system.svc.cluster.local
    Name:      kubernetes
    Address 1: 10.254.0.1 kubernetes.default.svc.cluster.local

Take a look inside the ``resolv.conf file`` of the busybox container
    
    kubectl exec busybox cat /etc/resolv.conf
    search default.svc.cluster.local svc.cluster.local cluster.local
    nameserver 10.254.3.100
    nameserver 8.8.8.8
    options ndots:5

Each time a new service starts on the cluster, it will register with the DNS letting all the pods to reach the new service.

## Configure GUI dashboard
Kubernetes dashboard provides a GUI through which we can manage Kubernetes work units. We can create, delete or edit all work unit from this dashboard. Kubernetes dashboard is deployed as a pod in a dedicated namespace.

Download the dashboard deploy from [here](https://github.com/kalise/Kubernetes-Lab-Tutorial/blob/master/examples/kubegui-deploy.yaml) and deploy it

    kubectl create -f kubegui-deploy.yaml
    deployment "kubernetes-dashboard" created

Download the dashboard service from [here](https://github.com/kalise/Kubernetes-Lab-Tutorial/blob/master/examples/kubegui-svc.yaml) and expose to the external port 8080

    kubectl create -f kubegui-svc.yaml
    service "kubernetes-dashboard" created

When objects are ready

    kubectl get all -n kube-system
    
    NAME                          DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/kubernetes-dashboard   1         1         1            1           23s
    NAME              DESIRED   CURRENT   READY     AGE
    rc/kube-dns-v20   1         1         1         1d
    NAME                       CLUSTER-IP       EXTERNAL-IP   PORT(S)         AGE
    svc/kube-dns               10.254.3.100     <none>        53/UDP,53/TCP   1d
    svc/kubernetes-dashboard   10.254.180.188   <none>        80/TCP          18s
    NAME                                 DESIRED   CURRENT   READY     AGE
    rs/kubernetes-dashboard-3543765157   1         1         1         23s
    NAME                                       READY     STATUS    RESTARTS   AGE
    po/kube-dns-v20-3xk4v                      3/3       Running   3          1d
    po/kubernetes-dashboard-3543765157-tbc49   1/1       Running   0          23s


point the browser to the public master IP address ``http://10.10.10.80:8080/ui``. Please, note, the dashboard requires the embedded DNS server for service discovery.
