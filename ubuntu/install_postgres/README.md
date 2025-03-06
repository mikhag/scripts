
# Postgresql HA-Solution



## Architecture


```
                 +---------------------------+
                 |  External Load Balancer   |
                 | (Azure)                   |
                 +------------+--------------+
                              |
          +---------+---------+
          |                   |                   
+---------v---------+ +--------v---------+
|  HAProxy Node 1   | |  HAProxy Node 2   |
|  (192.168.1.10)   | |  (192.168.1.20)   |
+---------+---------+ +--------+---------+
          |                   |
+---------v---------+ +--------v---------+
| Patroni Primary  | |  Patroni Replica  |
| PostgreSQL Node 1| |  PostgreSQL Node 2 |
+---------+---------+ +--------+---------+
          |                   |
+---------v--------------------------------+
|   etcd Cluster (for leader election)    |
+-----------------------------------------+


```
## Functions

### Postgresql-HA
A high availability PostgreSQL that can handle single node failure without loss of service. 


## Components

### External loadbalancer
An external loadbalancer is used to receive the requests and forward it to one of the available nodes in the cluster. 

### HAProxy
On each node of the cluster an HA-Proxy is installed, this monitors which server that is the master and forwards all operations to it. A readonly port is available aswell, that do not require operations on the master.

### ETCD
etcd is a distributed key-value store used for high availability and service coordination. It ensures consensus and leader election in Patroni-managed PostgreSQL clusters. etcd stores cluster state, ensures automatic failover, and enables synchronization across nodes using the Raft consensus algorithm for strong consistency and fault tolerance.

### Patroni
Patroni is a high-availability solution for PostgreSQL that automates failover, leader election, and replication management. It uses distributed consensus with etcd, to track cluster state, ensuring only one primary node exists. Patroni dynamically manages replicas, recovery, and reconfiguration, making PostgreSQL clusters resilient and self-healing.

### PostgreSQL
PostgreSQL is an open-source relational database management system known for reliability, extensibility, and SQL compliance. It supports ACID transactions, advanced indexing, replication, and high availability for scalable and secure data storage and management.

### UFW
UFW, the Uncomplicated Firewall, simplifies managing iptables rules on Ubuntu systems. It offers a user-friendly command-line interface to allow or block incoming and outgoing network traffic, effectively enhancing system security.


## Op-guides


### Ports
| Port | Description | Firewall |
| --- | --- | --- |
| 2379 | etcd status | Only accessible from the other node | 
| 2380 | etcd communication | Only accessible from the other node | 
| 5432 | HAproxy postgres-proxy RW | World accessable, Read and Write |
| 5433 | HAproxy postgres-proxy RO | World accessable, Readonly |
| 5442 | Postgressql | Only accessible from the other node |
| 8008 | Patroni cluster status | Only accessible from the other node |
| 8404 | HAproxy statusweb | World accessable (password-protected) | 

### Installation guide

1. Clone the git Repo


2. Start by hardening os
```
apt install python3-venv
python3 -m venv venv
source venv/bin/activate
pip3 install ansible-core
# This will apply some basic CIS-hardening
ansible-playbook -e ansible_user=root ./cis-playbook.yml
deactivate
rm -rf ./venv
```

3. Format and mount the unused disk, **WARNING: DESTRUCTIVE AND BASED ON GUESSWORK, DO NOT RUN WHEN PROD-DATA IS PRESENT**
```

# Appends mounted disk to list of appended disk, sorts and count. The one occuring only once is not mounted, and I **assume** that one should be formated
disk=$(((ls -1 /dev/sd[a-z]);(mount | grep -o "/dev/sd[a-z]" | sort | uniq)) | sort | uniq -c  | grep -e " 1 /dev/sd" | awk  '{print $2}')
mkfs.ext4 $disk
diskuuid=$(blkid -s UUID -o value $disk)

echo "UUID=$diskuuid /var/lib/postgres ext4  defaults 0 0" >> /etc/fstab; mkdir /var/lib/postgres; mount -a

```

4. Open inventory.yml and edit host information and passwords used in this instance

5. Run the following command on the primary and replica nodes
```
ansible-playbook -i inventory.yml ./deploy_patroni.yml
#If you run local without SSH, configure variables in command-line
ansible-playbook -e '{"ansible_hostname":"node2", "ansible_host":"10.20.110.112", "role":"replica", "peer_ip":"10.20.110.111", "peer_name":"node1"}'  -i inventory_localhost.yml deploy_patroni_localhost.yml 
```

6. Reboot the servers

7. verify that all services started correctly
```
systemctl status etcd

systemctl status patroni

systemctl status haproxy
```

8. Check Patroni status
```
patronictl -c /etc/patroni/config.yml list
+ Cluster: postgres (7474342875221584979) -----+-----------+----+-----------+
| Member        | Host               | Role    | State     | TL | Lag in MB |
+---------------+--------------------+---------+-----------+----+-----------+
| node1         | 10.20.110.111:5442 | Replica | streaming |  3 |         0 |
| node2         | 10.20.110.112:5442 | Leader  | running   |  3 |           |
+---------------+--------------------+---------+-----------+----+-----------+
```

9. If having troubles with the cluster not getting to correct status, you may have to rejoin the cluster in the correct order.

```
# On node 1 - Stop services
root@node1# systemctl stop patroni
root@node1# systemctl stop etcd
root@node1# systemctl stop haproxy

# On node 2 - Stop services
root@node2# systemctl stop patroni
root@node2# systemctl stop etcd
root@node2# systemctl stop haproxy

# On node1 and node2 - remove etcd database
root@node1# rm -rf /var/lib/etcd/*
root@node2# rm -rf /var/lib/etcd/*

# On node1 start etcd (will hang until node2 is started)
root@node1# systemctl start etcd
# On node2 start etcd (must be a couple of sec after node1)
root@node2# systemctl start etcd

# On node2 remove current postgres-db (Warning destructive action, make sure no data is present in DB!)
# !Note! if you remove the postgres folder on the primary node you have to run 'timescaledb-tune'.
root@node2# rm -rf /var/lib/postgresql/16/main/*

# On node1 - Start the remaining service
root@node1# systemctl start patroni
root@node1# systemctl start haproxy

# On node2 - Start the remaining service
root@node2# systemctl start patroni
root@node2# systemctl start haproxy

#Check status
root@node1# patronictl -c /etc/patroni/config.yml list
+ Cluster: postgres (7474342875221584979) -----+-----------+----+-----------+
| Member        | Host               | Role    | State     | TL | Lag in MB |
+---------------+--------------------+---------+-----------+----+-----------+
| node1         | 10.20.110.111:5442 | Replica | streaming |  3 |         0 |
| node2         | 10.20.110.112:5442 | Leader  | running   |  3 |           |
+---------------+--------------------+---------+-----------+----+-----------+
```



### Update of OS

1. Verify if the host is the leader
```
patronictl -c /etc/patroni/config.yml list
```


2. If it is the leader do a manual switchover
```
patronictl -c /etc/patroni/config.yml switchover
```

3. Verify that the Leader has been changed
```
patronictl -c /etc/patroni/config.yml list
```

4. Do the upgrade
```
apt update; apt upgrade
```

5. Reboot
```
reboot
```

6. Verify that all services has started correctly
```
systemctl status etcd

systemctl status patroni

systemctl status haproxy
```

7. Verify that the host has rejoined the cluster and is streaming
```
patronictl -c /etc/patroni/config.yml list
```

8. (optional) Retake the role as leader 
```
patronictl -c /etc/patroni/config.yml switchover
```

### Create a new database
```
#Connect to the databse
#Option1: Through the master-node
sudo -u postgres psql  -p 5442
#Option2: Through any host
psql -h <loadbalancer-ip> -p 5432 -U postgres -W
#Create a database
postgres=# CREATE DATABASE mydatabase;
#Create a user
postgres=# CREATE USER myuser WITH ENCRYPTED PASSWORD 'MySecurePassword';
#Grant all privileges to the database for the user
postgres=# GRANT ALL PRIVILEGES ON DATABASE mydatabase TO myuser;

```
### Troubleshooting

Test SQL
```
psql -h 10.20.110.112 -p 5432 -U postgres -W
postgres=# CREATE TABLE test_table (id SERIAL PRIMARY KEY, name TEXT NOT NULL, created_at TIMESTAMP DEFAULT NOW() );

postgres=# INSERT INTO test_table (name) VALUES ('Alice'), ('Bob'), ('Charlie');

postgres=# SELECT * FROM test_table;

postgres=# DROP TABLE test_table;

```

```
#List all nodes with status in patroni
patronictl -c /etc/patroni/config.yml list
#List all nodes with status etcd
etcdctl member list
```

```
#Switch leader in patroni
patronictl -c /etc/patroni/config.yml switchover
```

```
#Reinitiate a patronihost (replica)
patronictl -c /etc/patroni/config.yml reinit postgres nodeX
```

```
#clear etcd data, stop etcd on all hosts then run command, and start up etcd on primary, before replica
rm -rf /var/lib/etcd/*
```

```
#Check HAproxy status
watch 'echo "show stat" | sudo nc -U /var/run/haproxy.sock | cut -d "," -f 1,2,8-10,18 | column -s, -t'
```

* Problems that postgresql replication and superuser password doesn't match in patroni, which makes Patroni not being able to start or handle the cluster

### FIXME
* Better hardening-scripts
* Add another node to prevent split-brain scenarios
* Add monitoring capabilites
* SSL/TLS for etcd
* SSL/TLS for postgres and HAproxy


