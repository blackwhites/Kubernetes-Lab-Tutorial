#!/bin/bash -xv
#
# Copyright 2017 - Adriano Pezzuto
# https://github.com/kalise
#
# Setup NFS persistent volumes on kubernetes
for i in `seq -w 00 09`;
do
echo $i;
sed s/00/$i/g nfs-persistent-volume.yaml | kubectl create -f -;
done
