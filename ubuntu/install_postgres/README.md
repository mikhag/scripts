
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

### Status

✅ High Availability (✔ Patroni, HAProxy, Failover)

✅ Automatic Failover (✔ etcd + Patroni Leader Election)

✅ Scalability (✔ HAProxy Load Balancing, Read Replicas)

✅ No Single Point of Failure (✔ No VIP, External LB Used)

✅ Backup to local filesystem on both primary and replica

⚠ Missing: Replication Lag Protection (Add HAProxy checks)

⚠ Missing: Monitoring (Add Prometheus & Grafana)

⚠ Missing: Security (Enable SSL/TLS)



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


2. Enter the folder and run the following command
```
# This will apply some basic CIS-hardening
ansible-playbook -e ansible_user=root ./cis-playbook.yml
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


### Troubleshooting
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

* Problems that postgresql replication and superuser password doesn't match in patroni, which makes Patroni not being able to start or handle the cluster