FROM mterron/consul-betterscratch
MAINTAINER Miguel Terron <miguel.a.terron@gmail.com>

# We don't need to expose these ports in order for other containers on Triton
# to reach this container in the default networking environment, but if we
# leave this here then we get the ports as well-known environment variables
# for purposes of linking.
EXPOSE 8200

# Download Bifurcate
ENV BIFURCATE_VERSION=0.4.0
ADD https://github.com/novilabs/bifurcate/releases/download/v${BIFURCATE_VERSION}/bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz /
# Download Vault binary
ENV VAULT_VERSION=0.6.0
ADD https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip /
# Download Vault integrity file
ADD https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS /
# Download Consul CLI tool
ENV CONSULCLI_VERSION=0.3.0
ADD https://github.com/CiscoCloud/consul-cli/releases/download/v${CONSULCLI_VERSION}/consul-cli_${CONSULCLI_VERSION}_linux_amd64.tar.gz /
USER root
# Copy binaries. bin directory contains start_vault.sh vault-health.sh
COPY bin/ /bin
# Copy /etc (Vault config, Bifurcate config)
COPY etc/ /etc

# Install Vault & Bifurcate
RUN grep "linux_amd64.zip" vault_${VAULT_VERSION}_SHA256SUMS | sha256sum -sc &&\
    unzip -q -o vault_${VAULT_VERSION}_linux_amd64.zip -d /bin &&\
    tar xzf bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz -C /bin/ &&\
    tar xzf consul-cli_${CONSULCLI_VERSION}_linux_amd64.tar.gz &&\
    mv consul-cli_${CONSULCLI_VERSION}_linux_amd64/consul-cli /bin &&\
# Create Vault user
	/bin/busybox.static adduser -h /tmp -g 'Vault user' -s /dev/null -D -G consul vault &&\
	chown -R vault: /etc/bifurcate &&\
	chown -R vault: /etc/vault &&\
	chmod 660 /consul/config/consul.json &&\
# Cleanup
	rm -r vault_${VAULT_VERSION}_* bifurcate_${BIFURCATE_VERSION}_* consul-cli_${CONSULCLI_VERSION}_linux_amd64*

# Provide your own Vault config file and certificates
ONBUILD COPY config.hcl /etc/vault/
ONBUILD COPY consul.json /consul/config/
ONBUILD COPY tls/* /etc/tls/
ONBUILD COPY client_certificate.* /etc/tls/

VOLUME ["/etc/vault/"]

USER vault
CMD ["/bin/bifurcate","/etc/bifurcate/bifurcate.json"]
