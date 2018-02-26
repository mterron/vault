#!/bin/ash
log() {
	printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[INFO] start_vault.sh:",$0}'
}
loge() {
	printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[ERROR] start_vault.sh:",$0}' >&2
}

# Add the Consul CA to the trusted list
if [ ! -e /etc/ssl/certs/ca-consul.done ]; then
	cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt &&\
	touch /etc/ssl/certs/ca-consul.done
fi

# Acquire Consul master token
export CONSUL_HTTP_TOKEN="${CONSUL_ACL_MASTER_TOKEN:-$(jq -cr '.acl_master_token' /etc/consul/consul.json)}"

# Wait for Consul to be available
log 'Waiting for Consul instance...'
until (consul-cli status leader | jq -e 'if . == "" then false else true end' >/dev/null); do
	sleep 5s
done
log 'Consul is ready!'

# Allow service & node discovery without a token
consul-cli acl update --rule="node::read" --rule="service::read" anonymous

# Get Vault service name from the environment or config file. If both are empty
# it will default to "vault" as per
# https://www.vaultproject.io/docs/config/index.html#service
if [ -z "${VAULT_SERVICE_NAME:-$(jq -cr '.storage.consul.service' /etc/vault/config.json)}" ]; then
	VAULT_SERVICE_NAME=vault
fi
export VAULT_SERVICE_NAME

# Get Vault storage path in Consul KV
export VAULT_PATH=$(jq -cr '.storage.consul.path' /etc/vault/config.json)

# Remove old Vault service registrations
if [ "${SERVICEID:-$(consul-cli agent services | jq -cr '.[].ID|select(. == "consul"|not)|select(.|contains("." + env.HOSTNAME + ".")|not)')}" ]; then
	consul-cli service deregister "$SERVICEID"
fi

# If VAULT_CONSUL_TOKEN environment variable is not set and there's no token on
# the Vault configuration file, create an ACL in Consul with access to Vault's
# "path" on the K/V store and the "vault" service key and acquire a token
# associated with that ACL. Else use the environment variable if it exists or
# the existing token (from the config file)
if [ -z "${VAULT_CONSUL_TOKEN:-$(jq -cr '.storage.consul.token' /etc/vault/config.json)}" ]; then
	log 'Acquiring a Consul token for Vault'
	export VAULT_CONSUL_TOKEN=$(consul-cli acl create --name="$HOSTNAME Vault Token" --rule="key:${VAULT_PATH:-vault}:write" --rule="service:${VAULT_SERVICE_NAME:-vault}:write" --rule="node::write" --rule="agent::write" --rule="session::write" --rule="service::read")
elif [ -z "$VAULT_CONSUL_TOKEN" ]; then
	export VAULT_CONSUL_TOKEN=$(jq -cr '.storage.consul.token' /etc/vault/config.json)
fi

# Set Consul token & Datacenter in the config file
su -s /bin/sh vault -c "{ rm /etc/vault/config.json; jq '.storage.consul.service = env.VAULT_SERVICE_NAME | .storage.consul.token = env.VAULT_CONSUL_TOKEN | .storage.consul.datacenter = env.CONSUL_DC_NAME' > /etc/vault/config.json; } < /etc/vault/config.json"


# Fix privileges
if [ "$(uname -v)" = 'BrandZ virtual linux' ]; then # Joyent Triton (Illumos)
	# Assign a privilege spec to the process that allows it to lock memory
	/native/usr/bin/ppriv -s LI+PROC_LOCK_MEMORY $$
else
	# Assign a linux capability to the Vault binary that allows it to lock memory
	setcap 'cap_ipc_lock=+ep' /usr/local/bin/vault
fi

# Vault redirect address
export VAULT_REDIRECT_ADDR="https://${HOSTNAME}.node.${CONSUL_DOMAIN:-consul}:${VAULT_PORT:-8200}"
export VAULT_ADDR="https://active.${VAULT_SERVICE_NAME:-vault}.service.${CONSUL_DOMAIN:-consul}:${VAULT_PORT:-8200}"

# Unset local variables
unset VAULT_PATH
unset VAULT_CONSUL_TOKEN
unset VAULT_SERVICE_NAME
unset CONSUL_HTTP_TOKEN

log 'Starting Vault'
exec su-exec vault:consul vault server -config=/etc/vault/config.json -log-level=warn
