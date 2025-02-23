
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

### Postgresql



## Components

- An external loadbalancer is used to receive the requests and forward it to one of the available nodes in the cluster. 

### HAProxy

- On each node of the cluster an HA-Proxy is installed, this monitors which server that is the master and forwards all operations to it. A readonly port is available aswell, that do not require operations on the master.

### ETCD

### Patroni
- A postgres is installed with Patroni. Patroni monitors and automaticlly switch the master and replica if the master becomes unavailable.


### PostgreSQL

### UFW

## Op-guides


### Ports
| Port | Description |
| --- | --- |
| 2379 | etcd status |
| 2380 | etcd communication |
| 5442 | Postgressql |
| 5432 | HAproxy postgres-proxy RW |
| 5433 | HAproxy postgres-proxy RO |
| 8008 | Patroni cluster status |
| 8404 | HAproxy statusweb |

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

3. Open setup_postgres_cluster.sh and adjust the password and token at the top of the files (must match on both the primary and replica)

4. Run the following command on the primary and replica nodes
```
# Run this on the Primary node
./setup_postgres_cluster.sh --node-name node1 --node-ip 10.20.110.111 --peer-name node2 --peer-ip 10.20.110.112 --role primary
```

```
# Run this on the Replica node
./setup_postgres_cluster.sh --node-name node2 --node-ip 10.20.110.112 --peer-name node1 --peer-ip 10.20.110.111 --role replica
```

5. Reboot the servers

6. verify that all services started correctly
```
systemctl status etcd

systemctl status patroni

systemctl status haproxy
```

7. Check Patroni status
```
patronictl -c /etc/patroni/config.yml list
+ Cluster: postgres (7474342875221584979) -----+-----------+----+-----------+
| Member        | Host               | Role    | State     | TL | Lag in MB |
+---------------+--------------------+---------+-----------+----+-----------+
| 10.20.110.111 | 10.20.110.111:5442 | Replica | streaming |  3 |         0 |
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

1. Verify that the Leader has been changed
```
patronictl -c /etc/patroni/config.yml list
```

1. Do the upgrade
```
apt update; apt upgrade
```

1. Reboot
```
reboot
```

1. Verify that all services has started correctly
```
systemctl status etcd

systemctl status patroni

systemctl status haproxy
```

1. Verify that the host has rejoined the cluster and is streaming
```
patronictl -c /etc/patroni/config.yml list
```

2. (optional) Retake the role as leader 
```
patronictl -c /etc/patroni/config.yml switchover
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


* Problems that postgresql replication and superuser password doesn't match in patroni, which makes Patroni not being able to start or handle the cluster

### FIXME
* Better hardening-scripts
* Add another node to prevent split-brain scenarios
* Add monitoring capabilites
* SSL/TLS for etcd
* SSL/TLS for postgres and HAproxy
* Switch bash-script for automation (like ansible/puppet)