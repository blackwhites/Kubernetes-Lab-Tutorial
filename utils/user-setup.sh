#!/bin/bash -xv
#
# Copyright 2017 - Adriano Pezzuto
# https://github.com/kalise
#
for i in one two three four five six seven eight nine ten eleven twelve;
do
        USER=user-$i;
        echo "add password for user " $USER
        sudo passwd $USER
        sudo usermod -aG wheel $USER
        sudo mkdir /home/$USER/.ssh
        sudo cp /home/centos/.ssh/authorized_keys /home/$USER/.ssh/authorized_keys
        sudo chmod 700 /home/$USER/.ssh
        sudo chmod 600 /home/$USER/.ssh/authorized_keys
        sudo chown $USER:$USER /home/$USER/.ssh
        sudo chown $USER:$USER /home/$USER/.ssh/authorized_keys
        sudo cp ./kube-context-setup.sh /home/$USER/kube-context-setup.sh
        sudo chown $USER:$USER /home/$USER/kube-context-setup.sh
        sudo chmod u+x /home/$USER/kube-context-setup.sh
        sudo su -c "/home/$USER/kube-context-setup.sh" -s /bin/bash $USER
done
