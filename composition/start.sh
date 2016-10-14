#!/bin/bash

# check for prereqs
command -v docker >/dev/null 2>&1 || { printf "%s\n" "Docker is required, but does not appear to be installed. See https://docs.joyent.com/public-cloud/api-access/docker"; exit; }

# default values which can be overriden by -f or -p flags
export COMPOSE_FILE=
export COMPOSE_PROJECT_NAME=demo
export $(cat _env | grep CONSUL_CLUSTER_SIZE)

while getopts "f:p:" optchar; do
	case "${optchar}" in
		f) export COMPOSE_FILE=${OPTARG} ;;
		p) export COMPOSE_PROJECT_NAME=${OPTARG} ;;
	esac
done
shift $(( OPTIND - 1 ))

# give the docker remote api more time before timeout
export COMPOSE_HTTP_TIMEOUT=300

printf "%s\n" 'Starting a Consul service'
printf "%s\n" '>Pulling the most recent images'
#docker-compose pull
printf "%s\n" '>Starting initial container'
docker-compose up -d --remove-orphans

CONSUL_BOOTSTRAP_HOST="${COMPOSE_PROJECT_NAME}_vault_1"
printf "%s\n" "CONSUL_BOOTSTRAP_HOST is $CONSUL_BOOTSTRAP_HOST"

# Default for production
BOOTSTRAP_UI_IP=$(docker inspect -f '{{ .NetworkSettings.Networks.vault.IPAddress }}' $CONSUL_BOOTSTRAP_HOST)
printf "UI: $BOOTSTRAP_UI_IP\n"
# For running on local docker-machine
#if ! BOOTSTRAP_UI_IP=$(docker-machine ip); then {
#	BOOTSTRAP_UI_IP=127.0.0.1
#}
#fi

export CONSUL_BOOTSTRAP_HOST=$(docker inspect -f "{{ .NetworkSettings.Networks.vault.IPAddress}}" "$CONSUL_BOOTSTRAP_HOST")


# Wait for the bootstrap instance
printf '>Waiting for the bootstrap instance...'
until curl -fs --connect-timeout 1 http://"$BOOTSTRAP_UI_IP":8501/ui &> /dev/null; do
	printf '.'
	sleep .2
done

printf "%s\n" 'The bootstrap instance is now running'
printf "%s\n" "Dashboard: https://${BOOTSTRAP_UI_IP}:${BOOTSTRAP_UI_PORT}/ui/"
# Open browser pointing to the Consul UI
command -v open >/dev/null 2>&1 && open https://"$BOOTSTRAP_UI_IP":8501/ui/

# Scale up the cluster
printf "%s\n" "Scaling the Consul raft to ${CONSUL_CLUSTER_SIZE} nodes"
docker-compose -p "$COMPOSE_PROJECT_NAME" scale vault=$CONSUL_CLUSTER_SIZE

printf '>Waiting for Consul cluster quorum acquisition and stabilisation'
until docker-compose -p "$COMPOSE_PROJECT_NAME" exec vault /bin/ash -c 'consul info | grep leader_addr | grep "\d"'; do
	printf '.'
	sleep .2
done
sleep 5

printf "%s\n" 'Initialising Vault'
docker-compose -p "$COMPOSE_PROJECT_NAME" exec vault /bin/ash -c 'VAULT_ADDR="https://${HOSTNAME}.node.consul:8200" vault init -key-shares=1 -key-threshold=1'
for ((i=1; i <= CONSUL_CLUSTER_SIZE ; i++)); do
	docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index="$i" vault unseal_vault.sh
done
export VAULT_ADDR="https://$(docker inspect -f '{{ .NetworkSettings.Networks.vault.IPAddress}}' demo_vault_1):8200"
export VAULT_SKIP_VERIFY=1
export VAULT_TLS_SERVER_NAME=active.vault.service.consul
export VAULT_CACERT=../tls/vault.service.consul.pem
vault auth
vault audit-enable file file_path=/data/vault_audit.log
vault mount transit
printf "\e[1;91;5mRemember to delete the consul token from your home directory!\e[0m\n"
