#!/bin/bash

# Default values
PG_VERSION=16
PG_DATA_DIR="/var/lib/postgresql/${PG_VERSION}/main"
PATRONI_CONFIG="/etc/patroni/config.yml"
ETCD_CLUSTER_TOKEN="cewcewc3232rREWCrfe%%12"
POSTGRES_POSTGRES_PASSWORD="SuperSecret"
POSTGRES_REPLICATOR_PASSWORD="ReplicatorSecret"

# Help function
usage() {
    echo "Usage: $0 --node-ip <NODE_IP> --peer-ip <PEER_IP> --role <primary|replica>"
    echo "       $0 --help"
    echo ""
    echo "Example for primary: $0 --node-name node1 --node-ip 192.168.1.10 --peer-name node2 --peer-ip 192.168.1.20 --role primary"
    echo "Example for replica: $0 --node-name node2 --node-ip 192.168.1.20 --peer-name node1 --peer-ip 192.168.1.10 --role replica"
    exit 1
}

# Parse input arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --node-ip) NODE_IP="$2"; shift ;;
        --peer-ip) PEER_IP="$2"; shift ;;
        --node-name) NODE_NAME="$2"; shift ;;
        --peer-name) PEER_NAME="$2"; shift ;;
        --role) ROLE="$2"; shift ;;
        --help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate input
if [[ -z "$NODE_IP" || -z "$PEER_IP" || -z "$NODE_NAME" || -z "$PEER_NAME" || -z "$ROLE" ]]; then
    echo "Error: Missing required arguments!"
    usage
fi

if [[ "$ROLE" != "primary" && "$ROLE" != "replica" ]]; then
    echo "Error: Role must be 'primary' or 'replica'"
    usage
fi

# Install required packages
apt update && apt install -y postgresql-${PG_VERSION} etcd-server etcd-client patroni haproxy pgbouncer jq


# Configure etcd
mkdir -p /etc/etcd
cat <<EOF > /etc/default/etcd
ETCD_NAME="${NODE_NAME}"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="${ETCD_CLUSTER_TOKEN}"
ETCD_INITIAL_CLUSTER="${NODE_NAME}=http://${NODE_IP}:2380,${PEER_NAME}=http://${PEER_IP}:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${NODE_IP}:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://${NODE_IP}:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_ENABLE_V2="true"
EOF

systemctl enable --now etcd

#Change Postgres password to match configs
sudo -u postgres psql  -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${POSTGRES_REPLICATOR_PASSWORD}';"
sudo -u postgres psql  -c "ALTER USER postgres WITH PASSWORD '${POSTGRES_POSTGRES_PASSWORD}';"


#Disable postgres, let Patroni handle this
sudo systemctl disable postgresql

# Configure Patroni
cat <<EOF > $PATRONI_CONFIG
scope: postgres
namespace: /db/
name: ${NODE_NAME}

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
  listen: 0.0.0.0:5442
  connect_address: ${NODE_IP}:5442
  data_dir: ${PG_DATA_DIR}
  bin_dir: /usr/lib/postgresql/${PG_VERSION}/bin
  authentication:
    superuser:
      username: postgres
      password: "${POSTGRES_POSTGRES_PASSWORD}"
    replication:
      username: replicator
      password: "${POSTGRES_REPLICATOR_PASSWORD}"
  parameters:
    unix_socket_directories: '/var/run/postgresql'
EOF

echo "${NODE_IP}\t ${NODE_NAME}">> /etc/hosts
echo "${PEER_IP}\t ${PEER_NAME}">> /etc/hosts


if [ "${ROLE}" == "primary" ]; then


# Create a placeholder for postgresconfig if missing
if [ ! -f "${PG_DATA_DIR}/postgresql.conf" ]; then
  touch "${PG_DATA_DIR}/postgresql.conf"
fi

#Add pg_hba.conf
cat <<EOF > "${PG_DATA_DIR}/pg_hba.conf"
host    replication     replicator     ${PEER_IP}/32         md5
host    replication     replicator     ${NODE_IP}/32         md5
local   all             postgres                                peer
host    all             all             127.0.0.1/32            md5
host    all             all             0.0.0.0/0               md5
EOF

elif [ "${ROLE}" == "replica" ]; then
#Remove current postgres db from replica (Lets hope the variable isn't empty ;) ) 
  rm -rf "${PG_DATA_DIR}/*"
fi

systemctl enable --now patroni

# Configure HAProxy
cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log 127.0.0.1:514 local7
    maxconn 4096

defaults
    log global
    mode tcp
    retries 3
    timeout connect 10s
    timeout client 30s
    timeout server 30s

# Route write queries (Port 5432) only to master
frontend postgresql_write
    bind *:5432
    default_backend postgresql_master

backend postgresql_master
    balance roundrobin
    option httpchk GET /master
    http-check expect status 200
    server pg_node1 ${NODE_IP}:5442 check port 8008 rise 2 fall 3
    server pg_node2 ${PEER_IP}:5442 check port 8008 rise 2 fall 3 backup

# Route read queries (Port 5433) to all replicas
frontend postgresql_read
    bind *:5433
    default_backend postgresql_replicas

backend postgresql_replicas
    balance leastconn
    option httpchk GET /replica
    http-check expect status 200
    server pg_node1 ${NODE_IP}:5442 check port 8008 rise 2 fall 3
    server pg_node2 ${PEER_IP}:5442 check port 8008 rise 2 fall 3
EOF

systemctl restart haproxy
systemctl enable haproxy

# Configure PgBouncer
cat <<EOF > /etc/pgbouncer/pgbouncer.ini
[databases]
postgres = host=localhost port=5442 dbname=postgres

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
admin_users = postgres
pool_mode = transaction
EOF

echo "\"postgres\" \"${POSTGRES_POSTGRES_PASSWORD}\"" > /etc/pgbouncer/userlist.txt
systemctl restart pgbouncer
systemctl enable pgbouncer



#
# Lets create backupscripts
#
mkdir -p /tekniska/bin
cat <<EOF > /tekniska/bin/pg_backup.sh
#!/bin/bash

# Configuration
PG_PORT=5442
PG_USER="postgres"
BACKUP_DIR="/tekniska/backup/postgres"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

# Create directories if they don't exist
mkdir -p "$BACKUP_DIR/hourly" "$BACKUP_DIR/daily" "$BACKUP_DIR/weekly"

# Dump all databases
pg_dumpall -U "$PG_USER" -p "${PG_PORT}" | gzip > "$BACKUP_DIR/hourly/postgres_backup_$DATE.sql.gz"

# Rotate Backups
find "$BACKUP_DIR/hourly" -type f -mtime +1 -delete  # Keep last 24 hours
find "$BACKUP_DIR/daily" -type f -mtime +7 -delete   # Keep last 7 days
find "$BACKUP_DIR/weekly" -type f -mtime +28 -delete # Keep last 4 weeks

# Move to daily if it's midnight
if [ "$(date +%H)" -eq "00" ]; then
    cp "$BACKUP_DIR/hourly/postgres_backup_$DATE.sql.gz" "$BACKUP_DIR/daily/"
fi

# Move to weekly if it's Sunday at midnight
if [ "$(date +%u)" -eq "7" ] && [ "$(date +%H)" -eq "00" ]; then
    cp "$BACKUP_DIR/hourly/postgres_backup_$DATE.sql.gz" "$BACKUP_DIR/weekly/"
fi

EOF

chmod 711 /tekniska/bin/pg_backup.sh
mkdir -p /tekniska/backup/postgres
chown postgres:postgres /tekniska/backup/postgres
chmod 770 /tekniska/backup/postgres

cat <<EOF > /etc/cron.d/pgbackup

# Activity reports every 10 minutes everyday
0 * * * * postgres /tekniska/bin/pg_backup.sh

EOF


echo "✅ Patroni HA Cluster setup completed successfully on ${NODE_IP}"
