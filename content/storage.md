# Persistent Storage Model
Containers are ephemeral, meaning the container file system only lives as long as the container does. Volumes are simplest way to achieve data persistance. In kubernetes, a more flexible and powerful model is available.

This model is based on the following abstractions:

  * **PersistentVolume**: it models shared storage that has been provisioned by the cluster administrator. It is a resource in the cluster just like a node is a cluster resource. Persistent volumes are like standard kubernetes volumes, but having a lifecycle independent of any individual pod. Also they hide to the users the details of the implementation of the storage, e.g. NFS, iSCSI, or other cloud storage systems.

  * **PersistentVolumeClaim**: it is a request for storage by a user. It is similar to a pod. Pods consume node resources and persistent volume claims consume persistent volume objects. As pods can request specific levels of resources like cpu and memory, volume claimes claims can request the access modes like read-write or read-only and stoarage capacity.

In this section we're going to introduce this model by using simple examples. Please, refer to official documentation for more details.

  * [Local Persistent Volume](#local-persistent-volume)
  * [Volume Access Mode](#volume-access-mode)
  * [Volume Reclaim Policy](#volume-reclaim-policy)
  * [NFS Persistent Volume](#nfs-persistent-volume)

## Local Persistent Volume
Start by defining a persistent volume ``local-persistent-volume.yaml`` configuration file

```yaml
kind: PersistentVolume
apiVersion: v1
metadata:
  name: local
  labels:
    type: local
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data"
  persistentVolumeReclaimPolicy: Recycle
```

The configuration file specifies that the volume is at ``/data`` on the the cluster’s node. The volume type is ``hostPath`` meaning the volume is local to the host node. The configuration also specifies a size of 2GB and the access mode of ``ReadWriteOnce``, meanings the volume can be mounted as read write by a single node at time. The reclaim policy is ``Recycle`` meaning the volume can be used many times. 

Create the persistent volume

    kubectl create -f local-persistent-volume.yaml
    persistentvolume "local" created

and view information about it 

    kubectl get pv
    NAME                CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     REASON    AGE
    local               2Gi        RWO           Retain          Available                       10s

Now, we're going to use the volume above by creating a claiming for persistent storage. Create the following ``volume-claim.yaml`` configuration file
```yaml
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: volume-claim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1.5Mi
```

Note the claim is for 1.5MB of space where the the volume is 2GB. The claim will bound any volume meeting the minimum requirements specified into the claim definition. 

Create the claim

    kubectl create -f volume-claim.yaml
    persistentvolumeclaim "volume-claim" created

Check the status of persistent volume to see if it is bound

    kubectl get pv
    NAME                CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS    CLAIM                        REASON    AGE
    local               2Gi        RWO           Retain          Bound     default/volume-claim                   12m

Check the status of the claim

    kubectl get pvc
    NAME                 STATUS    VOLUME              CAPACITY   ACCESSMODES   AGE
    volume-claim         Bound     local               2Gi        RWO           6s

Create a ``nginx-pod-pvc.yaml`` configuration file for a nginx pod using the above claim for its html content directory
```yaml
---
kind: Pod
apiVersion: v1
metadata:
  name: nginx
  namespace: default
  labels:
spec:

  containers:
    - name: nginx
      image: nginx:latest
      ports:
        - containerPort: 80
          name: "http-server"
      volumeMounts:
      - mountPath: "/usr/share/nginx/html"
        name: html

  volumes:
    - name: html
      persistentVolumeClaim:
       claimName: volume-claim
```

Note that the pod configuration file specifies a persistent volume claim, but it does not specify a persistent volume. From the pod point of view, the claim is the volume. Please note that a claim must exist in the same namespace as the pod using the claim.

Create the nginx pod

    kubectl create -f nginx-pod-pvc.yaml
    pod "nginx" created

Accessing the nginx will return *403 Forbidden* since there are no html files to serve in the data volume

    kubectl get pod nginx -o yaml | grep IP
      hostIP: 10.10.10.86
      podIP: 172.30.5.2

    curl 172.30.5.2:80
    403 Forbidden

Let's login to the worker node and populate the data volume

    echo "Welcome to $(hostname)" > /data/index.html

Now try again to access the nginx application

     curl 172.30.5.2:80
     Welcome to kuben06

To test the persistence of the volume and related claim, delete the pod and recreate it

    kubectl delete pod nginx
    pod "nginx" deleted

    kubectl create -f nginx-pod-pvc.yaml
    pod "nginx" created

Locate the IP of the new nginx pod and try to access it

    kubectl get pod nginx -o yaml | grep podIP
      podIP: 172.30.5.2

    curl 172.30.5.2
    Welcome to kuben06

## Volume Access Mode
A persistent volume can be mounted on a host in any way supported by the resource provider. Different storage providers have different capabilities and access modes are set to the specific modes supported by that particular volume. For example, NFS can support multiple read write clients, but an iSCSI volume can be support only one.

The access modes are:

  * **ReadWriteOnce**: the volume can be mounted as read-write by a single node
  * **ReadOnlyMany**: the volume can be mounted read-only by many nodes
  * **ReadWriteMany**: the volume can be mounted as read-write by many nodes

Claims and volumes use the same conventions when requesting storage with specific access modes. Pods use claims as volumes. For volumes which support multiple access modes, the user specifies which mode desired when using their claim as a volume in a pod.

## Volume Reclaim Policy
When a pod claims for a volume, the cluster inspects the claim to find the volume meeting claim requirements and mounts that volume for the pod. Once a pod has a claim and that claim is bound, the bound volume belongs to the pod. 

A volume will be in one of the following status:

  * **Available**: a free resource that is not yet bound to a claim
  * **Bound**: the volume is bound to a claim
  * **Released**: the claim has been deleted, but the resource is not yet reclaimed by the cluster
  * **Failed**: the volume has failed its automatic reclamation

When a pod is removed, the claim can be removed. The volume is considered released when the claim is deleted, but it is not yet available for another claim.

In our example, delete the nginx pod and its volume claim

    kubectl delete pod nginx
    pod "nginx" deleted

    kubectl delete pvc volume-claim
    persistentvolumeclaim "volume-claim" deleted

See the status of the volume

    kubectl get pv persistent-volume
    
    NAME                CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     REASON    AGE
    local               2Gi        RWO           Recycle         Available                       9m

The volume becomes available to other claims since the claim policy is set to ``Recycle``. Volume claim policies currently supported are:

  * **Retain**: manual reclamation
  * **Recycle**: content of the volume is removed after volume unbound but volume still there, available for further bondings
  * **Delete**: associated storage volume is deleted when the volume is unbound.
  
Currently, only NFS and HostPath support recycling. 

## NFS Persistent Volume
In this section we're going to use a NFS storage backend. Main limit of local stoorage backend for container volumes is that storage area is tied to the host where it resides. If kubernetes moves the pod from another host, the moved pod is no more to access the storage area since local storage is not shared between multiple hosts of the cluster. To achieve a more useful storage backend we need to leverage on a shared storage technology like NFS.

For this example, we'll setup a simple NFS server on the master node. Please note, this is only an example and you should not implement it in production.

On the master node, install NFS server

    yum install -y nfs-utils

Make sure there is enough space under ``/mnt`` directory. We're going to create 10 NFS shares under this directory. To make it automatically, download the script ``nfs-setup.sh`` from [here](https://github.com/kalise/Kubernetes-Lab-Tutorial/blob/master/utils/nfs-setup.sh), change its permissions and execute it.

    chmod u+x nfs-setup.sh
    ll nfs-setup.sh
    -rwxr--r-- 1 root root 223 Apr 27 11:32 nfs-setup.sh

    ./nfs-setup.sh
    done

    ls -l /mnt
    total 0
    drwxr-xr-x 2 nfsnobody nfsnobody 23 Apr 27 11:49 PV00
    drwxr-xr-x 2 nfsnobody nfsnobody  6 Apr 27 11:33 PV01
    drwxr-xr-x 2 nfsnobody nfsnobody  6 Apr 27 11:33 PV02
    drwxr-xr-x 2 nfsnobody nfsnobody  6 Apr 27 11:33 PV03
    drwxr-xr-x 2 nfsnobody nfsnobody  6 Apr 27 11:33 PV04
    drwxr-xr-x 2 nfsnobody nfsnobody  6 Apr 27 11:33 PV05
    drwxr-xr-x 2 nfsnobody nfsnobody  6 Apr 27 11:33 PV06
    drwxr-xr-x 2 nfsnobody nfsnobody  6 Apr 27 11:33 PV07
    drwxr-xr-x 2 nfsnobody nfsnobody  6 Apr 27 11:33 PV08
    drwxr-xr-x 2 nfsnobody nfsnobody  6 Apr 27 11:33 PV09

Start and enable the NFS server daemons

    systemctl start nfs-server
    systemctl enable nfs-server
    systemctl status nfs-server rpcbind

Now our NFS server should be ready to serve shares to worker nodes. To make worker nodes able to consume these NFS shares, we neet to install NFS libraries on all the worker nodes by ``yum install -y nfs-utils``.

Define a persistent volume as in the ``nfs-persistent-volume.yaml`` configuration file
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs00
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  nfs:
    path: "/mnt/PV00"
    server: kubem04
  persistentVolumeReclaimPolicy: Recycle
```

Create the persistent volume

    kubectl create -f nfs-persistent-volume.yaml
    persistentvolume "nfs" created

    kubectl get pv nfs -o wide
    NAME      CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     REASON    AGE
    nfs00     500Mi      RWO           Recycle         Available                       11s

To avoid manual creation of the volume for each NFS share we create before, download the ``nfspv-setup.sh`` script from [here](https://github.com/kalise/Kubernetes-Lab-Tutorial/blob/master/utils/nfspv-setup.sh), check its permissions and execute it

    chmod u+x nfspv-setup.sh
    ./nfspv-setup.sh

    kubectl get pv
    NAME      CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     REASON    AGE
    nfs00     1Gi        RWO           Recycle         Available                       8s
    nfs01     1Gi        RWO           Recycle         Available                       8s
    nfs02     1Gi        RWO           Recycle         Available                       7s
    nfs03     1Gi        RWO           Recycle         Available                       7s
    nfs04     1Gi        RWO           Recycle         Available                       7s
    nfs05     1Gi        RWO           Recycle         Available                       6s
    nfs06     1Gi        RWO           Recycle         Available                       6s
    nfs07     1Gi        RWO           Recycle         Available                       6s
    nfs08     1Gi        RWO           Recycle         Available                       6s
    nfs09     1Gi        RWO           Recycle         Available                       5s

We have all persistent volumes modeling the NFS shares. Thanks to the persistent volume model, kubernetes hides the nature of storage and its complex setup to the applications. An user need only to claim volumes for their pods without deal with storage configuration and operations.

For example, create the ``nginx-pvc-template.yaml`` template for a nginx application having the html content dir on a shared storage 
```yaml
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  generation: 1
  labels:
    run: nginx
  name: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      run: nginx
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        run: nginx
    spec:
      containers:
      - image: nginx:latest
        imagePullPolicy: IfNotPresent
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
          name: "http-server"
        volumeMounts:
        - mountPath: "/usr/share/nginx/html"
          name: html
      volumes:
      - name: html
        persistentVolumeClaim:
          claimName: volume-claim
      dnsPolicy: ClusterFirst
      restartPolicy: Always

---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: volume-claim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi

---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    run: nginx
spec:
  ports:
  - protocol: TCP
    port: 8081
    targetPort: 80
    nodePort: 31000
  selector:
    run: nginx
  type: NodePort
```

The template above defines a nginx application based on a nginx deploy of 2 replicas. The nginx application requires a shared volume for its html content. This volume leverages on a volume claim of 500 MB of space with read-write-once policy. This is the only requirements for storage. The application does not have to deal with complexity of setup and admin an NFS share. In addition, the template expose the application as service to the outer world.

Deploy the application

    kubectl create -f nginx-pvc-template.yaml
    
    deployment "nginx" created
    persistentvolumeclaim "volume-claim" created
    service "nginx" created

Check everything is up and running

    kubectl get all -l run=nginx

    NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/nginx   2         2         2            2           1m
    NAME        CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
    svc/nginx   10.254.146.248   <nodes>       8081:31000/TCP   1m
    NAME                  DESIRED   CURRENT   READY     AGE
    rs/nginx-2480045907   2         2         2         1m
    NAME                        READY     STATUS    RESTARTS   AGE
    po/nginx-2480045907-r46m9   1/1       Running   0          1m
    po/nginx-2480045907-rw5tk   1/1       Running   0          1m

