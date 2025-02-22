

CIS-hardening from:
https://github.com/MVladislav/ansible-cis-ubuntu-2404

## Status

✅ High Availability (✔ Patroni, HAProxy, Failover)

✅ Automatic Failover (✔ etcd + Patroni Leader Election)

✅ Scalability (✔ HAProxy Load Balancing, Read Replicas)

✅ No Single Point of Failure (✔ No VIP, External LB Used)

⚠ Missing: Replication Lag Protection (Add HAProxy checks)

⚠ Missing: Backups (Add pgBackRest)

⚠ Missing: Monitoring (Add Prometheus & Grafana)

⚠ Missing: Security (Enable SSL/TLS)



## Architecture


```
                 +---------------------------+
                 |  External Load Balancer   |
                 | (AWS ELB, Nginx, F5, etc.)|
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
- An external loadbalancer is used to receive the requests and forward it to one of the available nodes in the cluster. 

**HAProxy**

- On each node of the cluster an HA-Proxy is installed, this monitors which server that is the master and forwards all operations to it. A readonly port is available aswell, that do not require operations on the master.

**ETCD**

**Patroni**
- A postgres is installed with Patroni. Patroni monitors and automaticlly switch the master and replica if the master becomes unavailable.


**pgbounder**

**postgres**

```
ansible-playbook -e ansible_user=root ./cis-playbook.yml
```

```
./setup_patroni_cluster.sh --node-ip 192.168.1.10 --peer-ip 192.168.1.20 --role primary
```

```
./setup_patroni_cluster.sh --node-ip 192.168.1.20 --peer-ip 192.168.1.10 --role replica
```

PORTS
2379 - etcd status
2380 - etcd communication
5442 - Postgressql
5432 - HAproxy postgres-proxy RW
5433 - HAproxy postgres-proxy RO
6432 - pgbouncer
8008 - Patroni cluster status
8404 - HAproxy statusweb



patronictl -c /etc/patroni/config.yml list
patronictl -c /etc/patroni/config.yml switchover

journalctl --no-pager --lines=50

etcdctl member list

./setup_postgres_cluster.sh --node-name node1 --node-ip 10.20.110.111 --peer-name node2 --peer-ip 10.20.110.112 --role primary


./setup_postgres_cluster.sh --node-name node2 --node-ip 10.20.110.112 --peer-name node1 --peer-ip 10.20.110.111 --role replica



apt update; apt install -y git-core;
git clone https://github.com/mikhag/scripts

