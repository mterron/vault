#!/bin/bash
# check for prereqs
command -v docker >/dev/null 2>&1 || { printf "%s\n" "Docker is required, but does not appear to be installed."; exit; }
command -v jq >/dev/null 2>&1 || { printf "%s\n" "jq is required, but does not appear to be installed."; exit; }
test -e _env || { printf "%s\n" "_env file not found"; exit; }
clear

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

BOOTSTRAP_UI_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONSUL_BOOTSTRAP_HOST")
export CONSUL_BOOTSTRAP_HOST="$BOOTSTRAP_UI_IP"

# Wait for the bootstrap instance
printf ' >Waiting for the bootstrap instance ...'
TIMER=0
until (docker-compose -p "$COMPOSE_PROJECT_NAME" exec vault su-exec consul: test -e /data/node-id)
do
    if [ $TIMER -gt 180 ]; then
        exit 1
    fi
    printf '.'
    sleep 3
    TIMER=$(( TIMER + 3))
done
printf "\e[0;32m done\e[0m\n"


# Scale up the cluster
printf "\n%s\n" "* Scaling the Consul raft to ${CONSUL_CLUSTER_SIZE} nodes"
docker-compose -p "$COMPOSE_PROJECT_NAME" up -d --no-recreate --scale vault=$CONSUL_CLUSTER_SIZE

# Wait for Consul to be available
printf ' >Waiting for Consul cluster quorum acquisition and stabilisation ...'
until (docker-compose -p "$COMPOSE_PROJECT_NAME" exec -w /tmp vault consul-healthcheck)
do
	printf '.'
	sleep 5
done
printf "\e[0;32m done\e[0m\n"


printf "\n%s\n" '* Bootstrapping Consul ACL system'
set -e

CONSUL_TOKEN=$(docker-compose -p "$COMPOSE_PROJECT_NAME" exec -w /tmp vault sh -c "su-exec consul curl --unix-socket /data/consul.http.sock -XPUT http://consul/v1/acl/bootstrap 2>/dev/null | jq -M -e -c -r '.ID' | tr -d '\000-\037'")
echo -e "Consul ACL token: \e[38;5;198m${CONSUL_TOKEN}\e[0m"
printf "%s\n\n" "Consul Dashboard: https://${BOOTSTRAP_UI_IP}:${BOOTSTRAP_UI_PORT:-8501}/ui/"
# Open browser pointing to the Consul UI
command -v open >/dev/null 2>&1 && open "https://$BOOTSTRAP_UI_IP:${BOOTSTRAP_UI_PORT:-8501}/ui/"

sleep 15

for ((i=1; i <= CONSUL_CLUSTER_SIZE ; i++)); do
	docker-compose -p "$COMPOSE_PROJECT_NAME" exec -e CONSUL_TOKEN=$CONSUL_TOKEN -e AGENT_TOKEN=$CONSUL_TOKEN --index=$i -w /tmp vault sh -c 'su-exec consul curl --unix-socket /data/consul.http.sock --header "X-Consul-Token: $CONSUL_TOKEN" --data "{\"Token\": \"$CONSUL_TOKEN\"}" -XPUT http://consul/v1/agent/token/acl_agent_token'
done


for ((i=1; i <= CONSUL_CLUSTER_SIZE ; i++)); do
	docker-compose -p "$COMPOSE_PROJECT_NAME" exec -e CONSUL_TOKEN=$CONSUL_TOKEN --index=$i vault sh -c 'echo ${CONSUL_TOKEN}>/tmp/CT'
done
set +e

docker-compose -p "$COMPOSE_PROJECT_NAME" exec -w /tmp -u vault vault sh -c 'VAULT_ADDR="https://${HOSTNAME}.node.consul:8200" vault operator init -status'

printf "\n* Initialising Vault\n"
docker-compose -p "$COMPOSE_PROJECT_NAME" exec -w /tmp -u vault vault sh -c 'VAULT_ADDR="https://${HOSTNAME}.node.consul:8200" vault operator init -key-shares=1 -key-threshold=1'

for ((i=1; i <= CONSUL_CLUSTER_SIZE ; i++)); do
	printf "\n%s\n" "* Unsealing ${COMPOSE_PROJECT_NAME}_vault_$i"
	docker-compose -p "$COMPOSE_PROJECT_NAME" exec -w /tmp --index="$i" vault unseal_vault.sh
done

printf ' >Waiting for Vault cluster stabilisation ...'
TIMER=0
until docker-compose -p "$COMPOSE_PROJECT_NAME" exec -e CONSUL_HTTP_TOKEN=$CONSUL_TOKEN vault sh -c "su-exec consul curl -sS --unix-socket /data/consul.http.sock http://consul/v1/catalog/service/vault?consistent=true&tag=active | jq -e '.[].Address' >/dev/null"
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
docker-compose -p "$COMPOSE_PROJECT_NAME" exec -u vault --index=1 vault vault login
printf "\n* Enabling Vault audit to file\n"
docker-compose -p "$COMPOSE_PROJECT_NAME" exec -u vault --index=1 vault vault audit enable file file_path=/data/vault_audit.log
#printf "\n* Mount KV secret backend\n"
#docker-compose -p "$COMPOSE_PROJECT_NAME" exec -u vault --index=1 vault vault secrets enable -path=secret -version=1 kv
printf "\n* Mount Transit secret backend\n"
docker-compose -p "$COMPOSE_PROJECT_NAME" exec -u vault --index=1 vault vault secrets enable transit
printf "\n* Cleaning up\n"
docker-compose -p "$COMPOSE_PROJECT_NAME" exec -u vault  --index=1 vault sh -c 'rm -f ~/.vault-token'

printf "%s\n\n" "Vault Dashboard: https://${BOOTSTRAP_UI_IP}:8200/ui/"
# Open browser pointing to the Vault UI
command -v open >/dev/null 2>&1 && open "https://$BOOTSTRAP_UI_IP:8200/ui/"
