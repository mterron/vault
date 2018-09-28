#!/bin/sh
logd() {
	if [ ${DEBUG:-} ]; then
		printf "[DEBUG] ${SCRIPT_NAME}: %s\n" "$@"
	fi
}
###################################################################################################

USER=$(id -u)
GROUP=$(id -g)
logd "Running as $USER:$GROUP"
set -e
# Trust CA
cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt
touch /etc/ssl/certs/ca-consul.done

# Fix run directory (Docker tmpfs bug)
mkdir -p -m 770 /run/consul/
chown consul:consul /run/consul