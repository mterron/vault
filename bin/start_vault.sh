#!/bin/ash
log() {
    printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[INFO] start_vault.sh:",$0}'
}
loge() {
    printf "%s\n" "$@"|awk '{print strftime("%FT%T%z",systime()),"[ERROR] start_vault.sh:",$0}' >&2
}

# Add the Consul CA to the trusted list
if  [ ! -e /etc/ssl/certs/ca-consul.done ]; then {
	cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt &&\
	touch /etc/ssl/certs/ca-consul.done
}
fi

# Wait for Consul to be available 
log 'Waiting for Consul instance...'
until (consul members >/dev/null 2>&1); do
    sleep 10s
done
#log 'Consul is ready!'

# Get Vault service name from the config file. If empty it will default to
# "vault" as per https://www.vaultproject.io/docs/config/index.html#service
VAULT_SERVICE_NAME=$(awk -F\" '/service =/{print $2}' /etc/vault/config.hcl | tr -d " /\"")

# If VAULT_CONSUL_TOKEN environment variable is not set and there's no token on 
# the Vault configuration file, create an ACL in Consul with access to Vault's 
# "path" on the K/V store and the "vault" service key and acquire a token 
# associated with that ACL
if [ -z "${VAULT_CONSUL_TOKEN:-$(awk -F\" '/token/{print $2}' /etc/vault/config.hcl)}" ]; then
	log 'Acquiring Consul token'
	VAULT_CONSUL_TOKEN=$(consul-cli --token="$(awk -F\" '/acl_master_token/{print $4}' /consul/config/consul.json)" --consul="$CONSUL_HTTP_ADDR" acl create --name="$HOSTNAME Vault Token" --rule="key:$(awk -F= '/path =/{print $2}' /etc/vault/config.hcl  | tr -d " /\""):write" --rule="service:${VAULT_SERVICE_NAME:-vault}:write")
fi
REPLACEMENT_CONSUL_TOKEN="s/#*token = .*/token = \"${VAULT_CONSUL_TOKEN}\"/"
sed -i "$REPLACEMENT_CONSUL_TOKEN" /etc/vault/config.hcl

REPLACEMENT_CONSUL_DATACENTER="s/#*datacenter = .*/datacenter = \"${CONSUL_DC_NAME}\"/"
sed -i "$REPLACEMENT_CONSUL_DATACENTER" /etc/vault/config.hcl

log 'Starting Vault'
exec vault server -config=/etc/vault/config.hcl -log-level=warn
