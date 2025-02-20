

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

- On each node of the cluster an HA-Proxy is installed, this monitors which server that is the master and forwards all operations to it. A readonly port is available aswell, that do not require operations on the master.

- A postgres is installed with Patroni. Patroni monitors and automaticlly switch the master and replica if the master becomes unavailable.




```
ansible-playbook -e ansible_user=root ./cis-playbook.yml
```

```
./setup_patroni_cluster.sh --node-ip 192.168.1.10 --peer-ip 192.168.1.20 --role primary
```

```
./setup_patroni_cluster.sh --node-ip 192.168.1.20 --peer-ip 192.168.1.10 --role replica
```