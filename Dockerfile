FROM mterron/consul
MAINTAINER Miguel Terron <miguel.a.terron@gmail.com>

EXPOSE 8200

ENV BIFURCATE_VERSION=0.5.0 \
	VAULT_VERSION=0.7.5 \
	CONSULCLI_VERSION=0.3.1

# Copy binaries. bin directory contains start_vault.sh vault-health.sh
COPY bin/ /bin
# Copy /etc (Vault config, Bifurcate config)
COPY etc/ /etc

USER root

# Download Bifurcate
RUN	wget -q --show-progress --progress=bar https://github.com/novilabs/bifurcate/releases/download/v${BIFURCATE_VERSION}/bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz &&\
# Download Vault binary & integrity file
	wget -q --show-progress --progress=bar https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip &&\
	wget -q --show-progress --progress=bar https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS &&\
# Download Consul CLI tool
	wget -q --show-progress --progress=bar https://github.com/CiscoCloud/consul-cli/releases/download/v${CONSULCLI_VERSION}/consul-cli_${CONSULCLI_VERSION}_linux_amd64.tar.gz &&\
# Install Bifurcate, Vault & Consul-cli
	tar xzf bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz -C /bin/ &&\
	grep "linux_amd64.zip" vault_${VAULT_VERSION}_SHA256SUMS | sha256sum -sc &&\
	unzip -q -o vault_${VAULT_VERSION}_linux_amd64.zip -d /bin/ &&\
	setcap 'cap_ipc_lock=+ep' /bin/vault &&\
	tar xzf consul-cli_${CONSULCLI_VERSION}_linux_amd64.tar.gz &&\
	mv consul-cli_${CONSULCLI_VERSION}_linux_amd64/consul-cli /bin &&\
# Create Vault user
	adduser -g 'Vault user' -s /dev/null -D -G consul vault &&\
	chown -R vault: /etc/vault &&\
	chmod 660 /etc/vault/config.hcl &&\
# Cleanup
	rm -rf vault_${VAULT_VERSION}_* bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz consul-cli_${CONSULCLI_VERSION}_*

# Provide your own Vault config file and certificates
ONBUILD COPY config.hcl /etc/vault/
ONBUILD COPY consul.json /etc/consul/
ONBUILD COPY tls/* /etc/tls/
ONBUILD COPY client_certificate.* /etc/tls/

# When you build on top of this image, put Consul data on a separate volume to
# avoid filesystem performance issues with Docker image layers
#VOLUME ["/data"]

CMD ["bifurcate","/etc/bifurcate/bifurcate.json"]
