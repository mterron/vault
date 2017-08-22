#!/bin/bash

# check for prereqs
command -v docker >/dev/null 2>&1 || { printf "%s\n" "Docker is required, but does not appear to be installed."; exit; }
command -v jq >/dev/null 2>&1 || { printf "%s\n" "jq is required, but does not appear to be installed."; exit; }
test -e _env || { printf "%s\n" "_env file not found"; exit; }

# default values which can be overriden by -f or -p flags
export COMPOSE_FILE=
export COMPOSE_PROJECT_NAME=demo
export $(grep CONSUL_CLUSTER_SIZE _env)

while getopts "f:p:" optchar; do
	case "${optchar}" in
		f) export COMPOSE_FILE=${OPTARG} ;;
		p) export COMPOSE_PROJECT_NAME=${OPTARG} ;;
	esac
done
shift $(( OPTIND - 1 ))

# give the docker remote api more time before timeout
export COMPOSE_HTTP_TIMEOUT=300

echo -e "Vault composition
 _______________
 \             /
  \    \e[36mo\e[34mo\e[36mo\e[0m    /
   \   \e[36mo\e[36mo\e[34mo\e[0m   /
    \  \e[34mo\e[34mo\e[36mo\e[0m  /
     \  \e[36mo\e[0m  /
      \   /
       \ /
        ∨"
printf "%s\n" "Starting a ${COMPOSE_PROJECT_NAME} ▽ Vault cluster"
printf "\n* Pulling the most recent images\n"
docker-compose pull
printf "\n* Starting initial container:\n"
docker-compose up -d --remove-orphans --force-recreate

CONSUL_BOOTSTRAP_HOST="${COMPOSE_PROJECT_NAME}_vault_1"

# Default for production
BOOTSTRAP_UI_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONSUL_BOOTSTRAP_HOST")

export CONSUL_BOOTSTRAP_HOST="$BOOTSTRAP_UI_IP"

# Wait for the bootstrap instance
printf ' >Waiting for the bootstrap instance ...'
sleep 5
TIMER=0
until docker-compose -p "$COMPOSE_PROJECT_NAME" exec vault sh -c 'test -e /data/node-id'
do
    if [ $TIMER -eq 20 ]; then
        break
    fi
    printf '.'
    sleep 5
    TIMER=$(( TIMER + 5))
done
printf "\e[0;32m done\e[0m\n"

printf "%s\n" 'The bootstrap instance is now running'
printf "%s\n" "Dashboard: https://${BOOTSTRAP_UI_IP}:${BOOTSTRAP_UI_PORT:-8501}/ui/"
# Open browser pointing to the Consul UI
command -v open >/dev/null 2>&1 && open "https://$BOOTSTRAP_UI_IP:${BOOTSTRAP_UI_PORT:-8501}/ui/"

# Scale up the cluster
printf "\n%s\n" "* Scaling the Consul raft to ${CONSUL_CLUSTER_SIZE} nodes"
docker-compose -p "$COMPOSE_PROJECT_NAME" scale vault=$CONSUL_CLUSTER_SIZE

printf ' >Waiting for Consul cluster quorum acquisition and stabilisation ...'
until docker-compose -p "$COMPOSE_PROJECT_NAME" exec vault sh -c "consul-cli status leader | jq -ce 'if . != \"\" then true else false end' >/dev/null"
do
	printf '.'
	sleep 5
done
printf "\e[0;32m done\e[0m\n"

docker-compose -p "$COMPOSE_PROJECT_NAME" exec vault sh -c 'VAULT_ADDR="https://${HOSTNAME}.node.consul:8200" vault init -check'
printf "\n* Initialising Vault\n"
docker-compose -p "$COMPOSE_PROJECT_NAME" exec vault sh -c 'VAULT_ADDR="https://${HOSTNAME}.node.consul:8200" vault init -key-shares=1 -key-threshold=1'
for ((i=1; i <= CONSUL_CLUSTER_SIZE ; i++)); do
	printf "\n%s\n" "* Unsealing ${COMPOSE_PROJECT_NAME}_vault_$i"
	docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index="$i" vault unseal_vault.sh
done
#export VAULT_ADDR="https://$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' demo_vault_1):8200"
#export VAULT_SKIP_VERIFY=1
#export VAULT_TLS_SERVER_NAME=active.vault.service.consul
#export VAULT_CAPATH=~/.vault/cert/
#export VAULT_CLIENT_CERT=~/.vault/cert/client_certificate.crt
#export VAULT_CLIENT_KEY=~/.vault/cert/client_certificate.key

printf ' >Waiting for Vault cluster stabilisation ...'
TIMER=0
until docker-compose -p "$COMPOSE_PROJECT_NAME" exec vault sh -c "consul-cli catalog service vault --consistent --tag active | jq -e '.[].ID' >/dev/null"
do
    if [ $TIMER -eq 20 ]; then
        break
    fi
    printf '.'
    sleep 1
    TIMER=$(( TIMER + 1))
done
printf "\e[0;32m done\e[0m\n"

printf "\n\nLogin to your new Vault cluster\n"
docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index=1 vault vault auth
printf "\n* Enabling Vault audit to file\n"
docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index=1 vault vault audit-enable file file_path=/data/vault_audit.log
printf "\n* Mount Transit secret backend\n"
docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index=1 vault vault mount transit
printf "\n* Cleaning up\n"
docker-compose -p "$COMPOSE_PROJECT_NAME" exec --index=1 vault sh -c 'rm /root/.vault-token'
