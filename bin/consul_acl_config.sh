#!/bin/sh
set -e
logd() {
	if [ ${DEBUG:-} ]; then
		printf "[DEBUG] ${SCRIPT_NAME}: %s\n" "$@"
	fi
}

# Acquire Consul master token
logd "Waiting for Consul token"
until [ -r /tmp/CT ]; do
	sleep 1
done
export CONSUL_HTTP_TOKEN=$(cat /tmp/CT)



# Allow service & node discovery without a token
logd "Setting anonymous ACL for service discovery"
curl -fsS --unix-socket /run/consul/consul.http.sock --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" --data '{"ID": "anonymous",  "Type": "client",  "Rules": "node \"\" { policy = \"read\" } service \"\" { policy = \"read\" }"}' -XPUT http://consul/v1/acl/update >/dev/null
logd "DONE"