#!/bin/bash -xv
#
# Copyright 2017 - Adriano Pezzuto
# https://github.com/kalise
#
# Setup NFS shares
for i in `seq -w 00 09`;
do
SHARE=/mnt/PV$i;
mkdir -p $SHARE;
chown nfsnobody:nfsnobody $SHARE;
echo "$SHARE *(no_root_squash,no_all_squash,no_subtree_check,rw,sync)" >>/etc/exports;
done
