# Cluster Networking
Kubernetes assumes that pods can communicate with other pods in the cluster, no matter of which host they land on. In a kubernetes cluster, every pod has its own IP address, so the cluster administrator does not need to create links between pods and never needs to deal with mapping container address to host address.

Kubernetes network model requires that the container address ranges should be routable. This is different from the default docker network model that provides a docker bridge with IP address in a given default subnet. In the default Docker model, each container will get an IP address in that subnet and uses the docker  bridge IP as it’s default gateway.

Kubernetes creates a cleaner model where pods can be treated much like virtual machines or physical hosts from the perspectives of addressing, naming, service discovery and load balancing. There are many ways to implement kubernetes networking model. In this tutorial we are using **Flannel**, a simple overlay networking daemon for kubernetes. Flannel is very simple to setup and use. Flannel gives a dedicated subnet to each docker bridge. Details about Flannel are [here](https://github.com/coreos/flannel).

After configuring Flannel daemon, the hosts get addresses for docker bridge:

![](../img/flannel.png?raw=true)

In the following sections we're going into a walk-through in kubernetes networking

   * [Pod Networking](#pod-networking)
   * [Exposing services](#exposing-services)
   * [Service discovery](#service-discovery)
   * [Accessing services](#accessing-services)

## Pod Networking
In a kubernetes cluster, when a pod is deployed, it gets an IP address from the docker bridge in the flannel overlay network.

Starting form the ``nginx-pod1.yaml`` file
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx1
  namespace: default
  labels:
    run: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
```

Create a nginx pod

    kubectl create -f nginx-pod1.yaml
    pod "nginx1" created

To get the IP address of the pod

    kubectl get pod nginx1 -o yaml | grep podIP
    podIP: 172.30.41.2

Thanks to the kubernetes networking model, we can access pod IP from any node in the cluster

      [root@kubem00 ~]# curl 172.30.41.2:80
      
      <!DOCTYPE html>
      <html>
      <head>
      <title>Welcome to nginx!</title>
      </head>
      <body>
      <h1>Welcome to nginx!</h1>
      <p><em>Thank you for using nginx.</em></p>
      </body>
      </html>

Please that the containers are not using port 80 on the host node whee the container is running. This means we can run multiple nginx pods on the same node all using the same container port 80 and access them from any other pod or node in the cluster using their IP. Start a second nginx pod

    kubectl create -f nginx-pod2.yaml
    pod "nginx2" created

    kubectl get pods
    NAME      READY     STATUS    RESTARTS   AGE
    nginx1    1/1       Running   0          12s
    nginx2    1/1       Running   0          8s

    kubectl get pods -l run=nginx -o yaml | grep podIP
    podIP: 172.30.41.2
    podIP: 172.30.41.3

Both pods run on the same host node, as we see from their IP address. We can still access both pods from any other node in the cluster

    [root@kubem00 ~]# curl 172.30.41.2:80
    Welcome to nginx!
    
    [root@kubem00 ~]# curl 172.30.41.3:80
    Welcome to nginx!

We do not need to expose container port on host to access nginx application as it is required in standard docker networking model. However we are not able to access nginx application from outside the kubernetes cluster. To achieve this we need to define a ngix service and expose the service to the external world.

## Exposing services
In kubernetes, services are used not only to provides access to other pods inside the same cluster but also to clients outside the cluster. In this section, we're going to create a deploy of two nginx replicas and expose them to the external world via nginx service.

Create the deploy

    kubectl create -f nginx-deploy.yaml
    deployment "nginx" created
    
    kubectl get pods
    NAME                    READY     STATUS    RESTARTS   AGE
    nginx-664452237-2r6sf   1/1       Running   0          4m
    nginx-664452237-hr532   1/1       Running   0          4m
    
    kubectl get pods -l run=nginx -o yaml | grep podIP
    podIP: 172.30.5.3
    podIP: 172.30.41.2

Pods are running on different host nodes as we can see from their IP addresses. To create a nginx service, we can expose the deploy on port 80 by running

    kubectl expose deploy/nginx --port=80 --target-port=80 --name=nginx-service
    service "nginx-service" exposed
    
    kubectl get services -l run=nginx
    NAME            CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
    nginx-service   10.254.247.153   <none>        80/TCP    36s

    kubectl describe service nginx-service
    Name:                   nginx-service
    Namespace:              default
    Labels:                 run=nginx
    Selector:               run=nginx
    Type:                   ClusterIP
    IP:                     10.254.247.153
    Port:                   <unset> 80/TCP
    Endpoints:              172.30.41.2:80,172.30.5.3:80
    Session Affinity:       None

This is equivalent to create the service from a ``nginx-svc.yaml`` file

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    run: nginx
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  selector:
    run: nginx
```

As we saw [before](https://github.com/kalise/Kubernetes-Tutorial/blob/master/content/core.md#services), any other pod in the cluster is able to access the nginx service without worring about pod IP addresses

    [root@kubem00 ~]# kubectl create -f busybox.yaml
    pod "busybox" created

    [root@kubem00 ~]# kubectl exec -it busybox sh
    / # wget -O - 10.254.247.153:80
    Welcome to nginx!

However, the service is still not reachable from any cluster host. If we try to access the service we do not get anything

    [root@kubem00 ~]# curl 10.254.247.153:80
    ^C
    [root@kubem00 ~]#

Without specifying the type of service, kubernetes by default uses the ``Type: ClusterIP`` option, which means that the new service is only exposed only within the cluster. It is kind of like internal kubernetes service, so not particularly useful if you want to accept external traffic.

When creating a service, kubernetes has four options of service types:

   * **ClusterIP**: it exposes the service only on a cluster internal IP making the service only reachable from within the cluster. This is the default Service Type.
   * **NodePort**: it exposes the service on each node public IP at a static port as defined in the NodePort option. It will be possible to access the service, from outside the cluster.
   * **LoadBalancer**: it exposes the service externally using an external load balancer.
   * **ExternalName**: it maps the service to the contents of the externalName option, e.g. search.google.com, by returning a name record with its value.

In this section we are going to use the NodePort service type to expose the service.

Delete the the service we created earlier

    kubectl delete svc/nginx-service
    service "nginx-service" deleted

Create a new service with NodePort type

    kubectl expose deploy/nginx --port=80 --target-port=80 --type=NodePort --name=nginx-service
    service "nginx-service" exposed

    kubectl describe svc/nginx-service
    Name:                   nginx-service
    Namespace:              default
    Labels:                 run=nginx
    Selector:               run=nginx
    Type:                   NodePort
    IP:                     10.254.114.251
    Port:                   <unset> 80/TCP
    NodePort:               <unset> 31608/TCP
    Endpoints:              172.30.41.2:80,172.30.5.3:80
    Session Affinity:       None

The NodePort type opens a service port on every worker node in the cluster. The service port is mapped to a port on the public IP node as in the NodePort. On any worker node, it is available at     
    
    
    [root@kuben05 ~]# netstat -natp | grep 31608
    tcp6       0      0 :::31608                :::*                    LISTEN      859/kube-proxy

    [root@kuben06 ~]# netstat -natp | grep 31608
    tcp6       0      0 :::31608                :::*                    LISTEN      863/kube-proxy

The kube-proxy service on the worker node, is in charge of doing this job as reported in the picture

![](../img/service-nodeport.png?raw=true)

Now it is possible to access the nginx service from ouside the cluster by pointing to any worker node

    [root@centos ~]# curl 10.10.10.85:31608
    Welcome to nginx!

    [root@centos ~]# curl 10.10.10.86:31608
    Welcome to nginx!

The NodePort is randomly selected from the 30000-32767 range. If you want to force a specific port, define it in a file``nginx-nodeport-svc.yaml``  
    
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    run: nginx
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 8090
  selector:
    run: nginx
  type: NodePort
```

Now that we have a port open on every worker node, we can configure an external load balancer or edge router to route the traffic to any of the worker nodes.

## Service discovery
To enable service name discovery in a kubernetes cluster, we need to configure an embedded DNS service to resolve all DNS queries from pods trying to access services. The embedded DNS should be manually installed during cluster setup since it is part of the cluster architecture, unless users are going to use other custom solutions for service discovery, e.g. consul.

The embedded DNS lives in the kube-system namespace

    kubectl get all -n kube-system
    NAME              DESIRED   CURRENT   READY     AGE
    rc/kube-dns-v20   1         1         1         1d

    NAME           CLUSTER-IP     EXTERNAL-IP   PORT(S)         AGE
    svc/kube-dns   10.254.3.100   <none>        53/UDP,53/TCP   1d

    NAME                    READY     STATUS    RESTARTS   AGE
    po/kube-dns-v20-3xk4v   3/3       Running   3          1d

It consists of a controller, a service and a pod running a DNS server, a dnsmaq for caching and healthz for liveness probe. Each time a user starts a new pod, kubernetes injects certain nameservice lookup configuration into new pods allowing to query the DNS records in the cluster. Each time a new service is created, kubernetes registers this service name into the embedded DNS server allowing all pods to query the DNS server for service name resolution.

Create a nginx deploy and create the service. Since we're not interested (yet) to expose the service outside the cluster, we leave the default service type, i.e. the ClusterIP mode. This allows only pods inside the cluster can access the service.

    kubectl create -f nginx-deploy.yaml
    deployment "nginx" created
    
    kubectl expose deploy/nginx --port=8080 --target-port=80 --name=nginx-service
    service "nginx-service" exposed

    kubectl get all -l run=nginx
    NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/nginx   2         2         2            2           3m
    NAME                CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
    svc/nginx-service   10.254.30.44   <none>        8080/TCP   33s
    NAME                 DESIRED   CURRENT   READY     AGE
    rs/nginx-664452237   2         2         2         3m
    NAME                       READY     STATUS    RESTARTS   AGE
    po/nginx-664452237-lkkxx   1/1       Running   0          3m
    po/nginx-664452237-n9pwd   1/1       Running   0          3m

Start a test pod and check if it access the nginx service

    kubectl create -f busybox.yaml
    pod "busybox" created

    kubectl exec -ti busybox -- wget 10.254.30.44:8080
    Connecting to 10.254.30.44:8080 (10.254.30.44:8080)
    index.html  200 OK  

Check if service DNS lookup configuration has been injectd by kubernetes

    kubectl exec -ti busybox -- cat /etc/resolv.conf
    search default.svc.cluster.local svc.cluster.local cluster.local
    nameserver 10.254.3.100
    nameserver 10.10.10.1
    nameserver 8.8.8.8
    options ndots:5

Now check if service discovery works by resolv the service name

    kubectl exec -ti busybox -- nslookup nginx-service
    Server:    10.254.3.100
    Address 1: 10.254.3.100 kube-dns.kube-system.svc.cluster.local
    Name:      nginx-service
    Address 1: 10.254.30.44 nginx-service.default.svc.cluster.local

This mechanism permits kubernetes pods to be linked each other without dealing with IP service assignment.

## Accessing services
In this section, we're going to deploy a WordPress application made of two services:

  1. Worpress service
  2. MariaDB service

We'll use the service discovery feature to permit the worpress pod to access the MariaDB pod without knowing the IP address. Also we'll expose the Worpress service to external world.

Create the MariaDB deploy as ``mariadb-deploy.yaml`` file
```yaml
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  generation: 1
  labels:
    run: mariadb
  name: mariadb
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: mariadb
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        run: mariadb
    spec:
      containers:
      - image: bitnami/mariadb:latest
        imagePullPolicy: Always
        name: mariadb
        ports:
        - containerPort: 3306
          protocol: TCP
        env:
        - name: MARIADB_ROOT_PASSWORD
          value: bitnami123
        - name: MARIADB_DATABASE
          value: workpress
        - name: MARIADB_USER
          value: bitnami
        - name: MARIADB_PASSWORD
          value: bitnami123
        volumeMounts:
        - name: mariadb-data
          mountPath: /bitnami/mariadb

      volumes:
      - name: mariadb-data
        emptyDir: {}
      dnsPolicy: ClusterFirst
      restartPolicy: Always
```

and deploy it 

    kubectl create -f mariadb-deploy.yaml
    deployment "mariadb" created
    
    kubectl get all -l run=mariadb
    NAME             DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/mariadb   1         1         1            1           38s
    NAME                   DESIRED   CURRENT   READY     AGE
    rs/mariadb-503575936   1         1         1         38s
    NAME                         READY     STATUS    RESTARTS   AGE
    po/mariadb-503575936-l2j57   1/1       Running   0          38s


Create a service called ``mariadb`` as ``mariadb-svc.yaml`` file
```yaml
apiVersion: v1
kind: Service
metadata:
  name: mariadb
  labels:
    run: mariadb
spec:
  ports:
  - protocol: TCP
    port: 3306
    targetPort: 3306
  selector:
    run: mariadb
```

and expose it as an internal service

    kubectl create -f mariadb-svc.yaml
    service "mariadb" created

    kubectl get service -l run=mariadb
    NAME      CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
    mariadb   10.254.223.163   <none>        3306/TCP   24s

    kubectl describe svc mariadb
    Name:                   mariadb
    Namespace:              default
    Labels:                 run=mariadb
    Selector:               run=mariadb
    Type:                   ClusterIP
    IP:                     10.254.223.163
    Port:                   <unset> 3306/TCP
    Endpoints:              172.30.41.4:3306
    Session Affinity:       None

This service will be used by the wordpress application as database backend. Thanks to the DNS service discovery embedded in the kubernetes cluster, the worpres application has not to take care of the mariadb database IP address. It should only reference a generic ``mariadb`` host. The embedded DNS will resolve this name into the real IP address of the mariadb service. Also, since we are not controlling where kubernetes start the mariadb pod, we are not worring about of the real IP of the mariadb pod.

Here the ``wordpress-deploy.yaml`` file defining the wordpress application
```yaml
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  generation: 1
  labels:
    run: blog
  name: wordpress
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: blog
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        run: blog
    spec:
      containers:
      - image: bitnami/wordpress:latest
        imagePullPolicy: Always
        name: wordpress
        ports:
        - containerPort: 80
          protocol: TCP
        - containerPort: 443
          protocol: TCP
        env:
        - name: MARIADB_HOST
          value: mariadb
        - name: MARIADB_PORT
          value: '3306'
        - name: WORDPRESS_DATABASE_NAME
          value: workpress
        - name: WORDPRESS_DATABASE_USER
          value: bitnami
        - name: WORDPRESS_DATABASE_PASSWORD
          value: bitnami123
        - name: WORDPRESS_USERNAME
          value: admin
        - name: WORDPRESS_PASSWORD
          value: password
        volumeMounts:
        - name: wordpress-data
          mountPath: /bitnami/wordpress
        - name: apache-data
          mountPath: /bitnami/apache
        - name: php-data
          mountPath: /bitnami/php

      volumes:
      - name: wordpress-data
        emptyDir: {}
      - name: apache-data
        emptyDir: {}
      - name: php-data
        emptyDir: {}

      dnsPolicy: ClusterFirst
      restartPolicy: Always
```

Deploy the wordpress application

    kubectl create -f wordpress-deploy.yaml
    deployment "wordpress" created

    kubectl get all -l run=blog
    NAME               DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/wordpress   1         1         1            1           9s
    NAME                      DESIRED   CURRENT   READY     AGE
    rs/wordpress-3277383805   1         1         1         9s
    NAME                            READY     STATUS    RESTARTS   AGE
    po/wordpress-3277383805-jdvrf   1/1       Running   0          9s

Now we need to expose the frontend wordpress application outside the cluster. To make this, we'll create a nodeport worpress service and expose it on a given port. Here the service definition as in the ``wordpress-svc.yaml`` file
```yaml
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  labels:
    run: blog
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 31080
  selector:
    run: blog
  type: NodePort
```

Create the service 

    kubectl create -f wordpress-svc.yaml
    service "wordpress" created

    kubectl get all -l run=blog
    NAME               DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/wordpress   1         1         1            1           4m
    NAME            CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
    svc/wordpress   10.254.62.237   <nodes>       80:31080/TCP   4s
    NAME                      DESIRED   CURRENT   READY     AGE
    rs/wordpress-3277383805   1         1         1         4m
    NAME                            READY     STATUS    RESTARTS   AGE
    po/wordpress-3277383805-jdvrf   1/1       Running   0          4m

    kubectl describe svc/wordpress
    Name:                   wordpress
    Namespace:              default
    Labels:                 run=blog
    Selector:               run=blog
    Type:                   NodePort
    IP:                     10.254.62.237
    Port:                   <unset> 80/TCP
    NodePort:               <unset> 31080/TCP
    Endpoints:              172.30.41.5:80
    Session Affinity:       None

This service will be accessible from all worker nodes in the cluster thanks to the kube-proxy job. Try to access it from any external client by pointing to any of the worker node

    wget 10.10.10.86:31080
    --2017-04-25 18:01:16--  http://10.10.10.86:31080/
    Connecting to 10.10.10.86:31080... connected.
    HTTP request sent, awaiting response... 200 OK
    Length: unspecified [text/html]
    Saving to: ‘index.html’
    2017-04-25 18:01:18 (3.45 MB/s) - ‘index.html’ saved [51713]
