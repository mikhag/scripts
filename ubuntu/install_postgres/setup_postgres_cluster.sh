#!/bin/bash

# Default values
PG_VERSION=16
PG_DATA_DIR="/var/lib/postgresql/${PG_VERSION}/main"
PATRONI_CONFIG="/etc/patroni.yml"

# Help function
usage() {
    echo "Usage: $0 --node-ip <NODE_IP> --peer-ip <PEER_IP> --role <primary|replica>"
    echo "       $0 --help"
    echo ""
    echo "Example for primary: $0 --node-ip 192.168.1.10 --peer-ip 192.168.1.20 --role primary"
    echo "Example for replica: $0 --node-ip 192.168.1.20 --peer-ip 192.168.1.10 --role replica"
    exit 1
}

# Parse input arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --node-ip) NODE_IP="$2"; shift ;;
        --peer-ip) PEER_IP="$2"; shift ;;
        --role) ROLE="$2"; shift ;;
        --help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate input
if [[ -z "$NODE_IP" || -z "$PEER_IP" || -z "$ROLE" ]]; then
    echo "Error: Missing required arguments!"
    usage
fi

if [[ "$ROLE" != "primary" && "$ROLE" != "replica" ]]; then
    echo "Error: Role must be 'primary' or 'replica'"
    usage
fi

# Install required packages
apt update && apt install -y postgresql-${PG_VERSION} etcd patroni haproxy pgbouncer jq

# Configure etcd
mkdir -p /etc/etcd
cat <<EOF > /etc/etcd/etcd.conf.yaml
initial-cluster-token: PostgreSQL_HA_Cluster_1
initial-cluster-state: new
initial-cluster: node1=http://${NODE_IP}:2380,node2=http://${PEER_IP}:2380
data-dir: /var/lib/etcd
initial-advertise-peer-urls: http://${NODE_IP}:2380 
listen-peer-urls: http://${NODE_IP}:2380
advertise-client-urls: http://${NODE_IP}:2379
listen-client-urls: http://${NODE_IP}:2379
EOF

systemctl enable --now etcd

# Configure Patroni
cat <<EOF > $PATRONI_CONFIG
scope: postgres
namespace: /db/
name: ${NODE_IP}

restapi:
  listen: 0.0.0.0:8008
  connect_address: ${NODE_IP}:8008

etcd:
  hosts: ${NODE_IP}:2379,${PEER_IP}:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 512MB
  initdb:
  - encoding: UTF8
  - data-checksums

postgresql:
  listen: 0.0.0.0:5432
  connect_address: ${NODE_IP}:5432
  data_dir: ${PG_DATA_DIR}
  bin_dir: /usr/lib/postgresql/${PG_VERSION}/bin
  authentication:
    superuser:
      username: postgres
      password: "SuperSecret"
    replication:
      username: replicator
      password: "ReplicatorSecret"
  parameters:
    unix_socket_directories: '/var/run/postgresql'
EOF

systemctl enable --now patroni

# Configure HAProxy
cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log stdout format raw
    maxconn 4096

defaults
    log global
    mode tcp
    retries 3
    timeout connect 10s
    timeout client 30s
    timeout server 30s

# 🔹 Route write queries (Port 5432) only to master
frontend postgresql_write
    bind *:5432
    default_backend postgresql_master

backend postgresql_master
    balance roundrobin
    option httpchk GET /master
    http-check expect status 200
    server pg_node1 ${NODE_IP}:5432 check port 8008 rise 2 fall 3
    server pg_node2 ${PEER_IP}:5432 check port 8008 rise 2 fall 3 backup

# 🔹 Route read queries (Port 5433) to all replicas
frontend postgresql_read
    bind *:5433
    default_backend postgresql_replicas

backend postgresql_replicas
    balance leastconn
    option httpchk GET /replica
    http-check expect status 200
    server pg_node1 ${NODE_IP}:5432 check port 8008 rise 2 fall 3
    server pg_node2 ${PEER_IP}:5432 check port 8008 rise 2 fall 3
EOF

systemctl restart haproxy
systemctl enable haproxy

# Configure PgBouncer
cat <<EOF > /etc/pgbouncer/pgbouncer.ini
[databases]
postgres = host=localhost port=5432 dbname=postgres

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
admin_users = postgres
pool_mode = transaction
EOF

echo "\"postgres\" \"SuperSecret\"" > /etc/pgbouncer/userlist.txt
systemctl restart pgbouncer
systemctl enable pgbouncer

echo "✅ Patroni HA Cluster setup completed successfully on ${NODE_IP}"
