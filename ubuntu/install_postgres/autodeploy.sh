#!/bin/bash

#This script will deploy and 


export PRIMARY_NAME=vm-l-pgsql-dev-01;
export PRIMARY_IP="10.20.110.111";
export REPLICA_NAME=vm-l-pgsql-dev-02;
export REPLICA_IP="10.20.110.112";

# Install  dependencies
apt update
apt install -y ansible git gpg vim

#Get repo and go to correct folder
git clone https://github.com/mikhag/scripts
cd scripts/ubuntu/install_postgres

# Apply hardening
ansible-playbook -e ansible_user=root ./cis-playbook.yml

# Appends mounted disk to list of appended disk, sorts and count. The one occuring only once is not mounted, and I **assume** that one should be formated
disk=$(((ls -1 /dev/sd[a-z]);(mount | grep -o "/dev/sd[a-z]" | sort | uniq)) | sort | uniq -c  | grep -e " 1 /dev/sd" | awk  '{print $2}')
mkfs.ext4 $disk
#Get UUID
diskuuid=$(blkid -s UUID -o value $disk)
# Add to fstab and mount it
echo "UUID=$diskuuid /var/lib/postgres ext4  defaults 0 0" >> /etc/fstab; mkdir /var/lib/postgres; mount -a

if [ $(echo $HOSTNAME | grep -e "1$") ]; then
    ansible-playbook -e "{'ansible_hostname':'${PRIMARY_NAME}', 'ansible_host':'${PRIMARY_IP}', 'role':'primary', 'peer_ip':'${REPLICA_IP}', 'peer_name':'${REPLICA_NAME}'}"  -i inventory_localhost.yml deploy_patroni_localhost.yml 
else
    ansible-playbook -e "{'ansible_hostname':'${REPLICA_NAME}', 'ansible_host':'${REPLICA_IP}', 'role':'replica', 'peer_ip':'${PRIMARY_IP}', 'peer_name':'${PRIMARY_NAME}'}"  -i inventory_localhost.yml deploy_patroni_localhost.yml 
fi

