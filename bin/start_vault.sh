#!/bin/ash
set -e
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

# Wait for Consul to be available
log 'Waiting for Consul instance...'
until (consul info 2>/dev/null | grep leader_addr | grep -q '\d'); do
	sleep 5s
done
log 'Consul is ready!'

# Acquire Consul master token
CONSUL_TOKEN="${CONSUL_ACL_MASTER_TOKEN:-$(jq -c -r '.acl_master_token' /etc/consul/consul.json)}"

# Allow service discovery without a token
consul-cli --token="$CONSUL_TOKEN" --consul="$CONSUL_HTTP_ADDR" acl update --rule="service::read" anonymous

# Get Vault service name from the config file. If empty it will default to
# "vault" as per https://www.vaultproject.io/docs/config/index.html#service
if [ -z "${VAULT_SERVICE_NAME:-$(jq -c -r '.storage.consul.service' /etc/vault/config.json)}" ]; then
	export VAULT_SERVICE_NAME=vault
fi

VAULT_PATH=$(jq -c -r '.storage.consul.path' /etc/vault/config.json)

# Obsolete as of vault 0.6.0
# Remove old Vault service registrations
#consul-cli --token="$CONSUL_TOKEN" --consul="$CONSUL_HTTP_ADDR" agent services | awk '/ID/{print $2}' | grep -v consul | grep -v "$(hostname -i)"|tr -d ",\""|xargs -r -n 1 -I SERVICEID consul-cli --token="$CONSUL_TOKEN" --consul="$CONSUL_HTTP_ADDR" service deregister SERVICEID

# If VAULT_CONSUL_TOKEN environment variable is not set and there's no token on
# the Vault configuration file, create an ACL in Consul with access to Vault's
# "path" on the K/V store and the "vault" service key and acquire a token
# associated with that ACL. Else use the environment variable if it exists or
# the existing token (from the config file)
if [ -z "${VAULT_CONSUL_TOKEN:-$(jq -c -r '.storage.consul.token' /etc/vault/config.json)}" ]; then
	log 'Acquiring a Consul token for Vault'
	export VAULT_CONSUL_TOKEN=$(consul-cli --token="$CONSUL_TOKEN" --consul="$CONSUL_HTTP_ADDR" acl create --name="$HOSTNAME Vault Token" --rule="key:${VAULT_PATH:-vault}:write" --rule="service:${VAULT_SERVICE_NAME:-vault}:write" --rule="service::read")
elif [ -z "$VAULT_CONSUL_TOKEN" ]; then
	export VAULT_CONSUL_TOKEN=$(jq -c -r '.storage.consul.token' /etc/vault/config.json)
fi

# Set Consul token & Datacenter in the config file
{ rm /etc/vault/config.json; jq '.storage.consul.service = env.VAULT_SERVICE_NAME | .storage.consul.token = env.VAULT_CONSUL_TOKEN | .storage.consul.datacenter = env.CONSUL_DC_NAME' > /etc/vault/config.json; } < /etc/vault/config.json
unset VAULT_CONSUL_TOKEN
unset VAULT_SERVICE_NAME

# Detect Joyent Triton
# Assign a privilege spec to the process that allows it to lock memory
if [ "$(uname -v)" = 'BrandZ virtual linux' ]; then
    /native/usr/bin/ppriv -s LI+PROC_LOCK_MEMORY $$
fi

log 'Starting Vault'
exec su-exec vault:consul vault server -config=/etc/vault/config.json -log-level=warn
