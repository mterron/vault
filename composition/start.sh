#!/bin/bash

# check for prereqs
command -v docker >/dev/null 2>&1 || { printf "%s\n" "Docker is required, but does not appear to be installed. See https://docs.joyent.com/public-cloud/api-access/docker"; exit; }

# default values which can be overriden by -f or -p flags
export COMPOSE_FILE=
export COMPOSE_PROJECT_NAME=demo
export CONSUL_QUORUM_SIZE=3

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
# Set initial bootstrap host to localhost
export CONSUL_BOOTSTRAP_HOST=127.0.0.1
printf "%s\n" '>Starting initial container'
docker-compose up -d --remove-orphans


CONSUL_BOOTSTRAP_HOST="${COMPOSE_PROJECT_NAME}_vault_1"
printf "%s\n" "CONSUL_BOOTSTRAP_HOST is ${COMPOSE_PROJECT_NAME}_vault_1"

# Default for production
#BOOTSTRAP_UI_IP=$(docker inspect -f "{{.NetworkSettings.Networks.${COMPOSE_PROJECT_NAME}_default.IPAddress}}" $CONSUL_BOOTSTRAP_HOST)
#
# For running on local docker-machine
if ! BOOTSTRAP_UI_IP=$(docker-machine ip 2>/dev/null); then {
	BOOTSTRAP_UI_IP=127.0.0.1
}
fi

printf "%s\n" " [DEBUG] BOOTSTRAP_UI_IP is $BOOTSTRAP_UI_IP"
BOOTSTRAP_UI_PORT=$(docker port "$CONSUL_BOOTSTRAP_HOST" | awk -F: '/8501/{print$2}')
printf "%s\n" " [DEBUG] BOOTSTRAP_UI_PORT is $BOOTSTRAP_UI_PORT"

export CONSUL_BOOTSTRAP_HOST=$(docker inspect -f "{{.NetworkSettings.Networks.vault.IPAddress}}" "$CONSUL_BOOTSTRAP_HOST")
# export CONSUL_BOOTSTRAP_HOST=$(docker inspect -f "{{.NetworkSettings.Networks.${COMPOSE_PROJECT_NAME}_default.IPAddress}}" "$CONSUL_BOOTSTRAP_HOST")
#CONSUL_BOOTSTRAP_HOST=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $CONSUL_BOOTSTRAP_HOST)

printf "%s\n" " [DEBUG] CONSUL_BOOTSTRAP_HOST is ${CONSUL_BOOTSTRAP_HOST}"

# Wait for the bootstrap instance
printf '>Waiting for the bootstrap instance...'
until curl -fs --connect-timeout 1 http://"$BOOTSTRAP_UI_IP":"$BOOTSTRAP_UI_PORT"/ui &> /dev/null; do
    printf '.'
    sleep .5
done

printf "%s\n" 'The bootstrap instance is now running'
printf "%s\n" "Dashboard: https://$BOOTSTRAP_UI:$BOOTSTRAP_UI_PORT/ui/"
# Open browser pointing to the Consul UI
command -v open >/dev/null 2>&1 && open https://"$BOOTSTRAP_UI_IP":"$BOOTSTRAP_UI_PORT"/ui/ >/dev/null 2>&1
command -v open >/dev/null 2>&1 && xdg-open https://"$BOOTSTRAP_UI_IP":"$BOOTSTRAP_UI_PORT"/ui/ >/dev/null 2>&1

# Scale up the cluster
printf "%s\n" 'Scaling the Consul raft to three nodes'
docker-compose -p "$COMPOSE_PROJECT_NAME" scale vault=$CONSUL_QUORUM_SIZE
printf "%s\n" 'Waiting for Consul cluster quorum acquisition and stabilisation'
sleep 10
printf "%s\n" 'Initialising Vault'

#docker-compose -p "$COMPOSE_PROJECT_NAME" exec vault init_vault.sh
docker-compose -p "$COMPOSE_PROJECT_NAME" exec vault /bin/ash -c 'VAULT_ADDR="https://${HOSTNAME}.node.consul:8200" vault init -key-shares=1 -key-threshold=1'
docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index=1 vault unseal_vault.sh
docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index=2 vault unseal_vault.sh
docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index=3 vault unseal_vault.sh
docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index=1 vault /bin/ash -c 'VAULT_ADDR="https://${HOSTNAME}.node.consul:8200" vault auth'
docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index=1 vault /bin/ash -c 'VAULT_ADDR="https://${HOSTNAME}.node.consul:8200" vault audit-enable file file_path=/data/vault_audit.log'