FROM mterron/consul
MAINTAINER Miguel Terron <miguel.a.terron@gmail.com>

EXPOSE 8200

ENV BIFURCATE_VERSION=0.5.0 \
	VAULT_VERSION=0.7.3

# Copy binaries. bin directory contains start_vault.sh vault-health.sh and consul-cli
COPY bin/ /usr/local/bin
# Copy /etc (Vault config, Bifurcate config)
COPY etc/ /etc

USER root

# Download Bifurcate
RUN	curl -L# -obifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz https://github.com/novilabs/bifurcate/releases/download/v${BIFURCATE_VERSION}/bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz &&\
# Download Vault binary & integrity file
	curl -L# -ovault_${VAULT_VERSION}_linux_amd64.zip https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip &&\
	curl -L# -ovault_${VAULT_VERSION}_SHA256SUMS https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS &&\
# Install Bifurcate, Vault
	tar xzf bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz -C /usr/local/bin/ &&\
	grep "linux_amd64.zip" vault_${VAULT_VERSION}_SHA256SUMS | sha256sum -sc &&\
	unzip -q -o vault_${VAULT_VERSION}_linux_amd64.zip -d /usr/local/bin/ &&\
	setcap 'cap_ipc_lock=+ep' /usr/local/bin/vault &&\
# Create Vault user & group and add root to the vault group
	adduser -g 'Vault user' -s /dev/null -D vault &&\
	adduser vault consul &&\
	adduser root vault &&\
	chown -R vault: /etc/vault &&\
	chmod 660 /etc/vault/config.json &&\
# Cleanup
	rm -rf vault_${VAULT_VERSION}_* bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz

# Provide your own Vault config file and certificates
ONBUILD COPY config.json /etc/vault/
ONBUILD COPY consul.json /etc/consul/
ONBUILD COPY tls/* /etc/tls/
ONBUILD COPY client_certificate.* /etc/tls/

# When you build on top of this image, put Consul data on a separate volume to
# avoid filesystem performance issues with Docker image layers
#VOLUME ["/data"]

ENTRYPOINT ["bifurcate","/etc/bifurcate/bifurcate.json"]
