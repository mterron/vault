FROM mterron/consul
MAINTAINER Miguel Terron <miguel.a.terron@gmail.com>

ARG BUILD_DATE
ARG VCS_REF
ARG HASHICORP_PGP_KEY=51852D87348FFC4C
ARG VAULT_VERSION=0.9.0

ENV BIFURCATE_VERSION=0.5.0

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-url="https://github.com/mterron/vault.git" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.schema-version="1.0.0-rc.1" \
      org.label-schema.version=$VAULT_VERSION \
      org.label-schema.description="Vault secure production ready Docker image"

# Download Bifurcate
RUN apk -q --no-cache add ca-certificates gnupg wget &&\
	gpg --keyserver pgp.mit.edu --recv-keys 91A6E7F85D05C65630BEF18951852D87348FFC4C &&\
	wget -nv --progress=bar:force --show-progress https://github.com/novilabs/bifurcate/releases/download/v${BIFURCATE_VERSION}/bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz &&\
# Download Vault binary & integrity file
	wget -nv --progress=bar:force --show-progress https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip &&\
	wget -nv --progress=bar:force --show-progress https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS &&\
	wget -nv --progress=bar:force --show-progress https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS.sig &&\
# Install Bifurcate, Vault
	tar xzf bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz -C /usr/local/bin/ &&\
	gpg --batch --verify vault_${VAULT_VERSION}_SHA256SUMS.sig vault_${VAULT_VERSION}_SHA256SUMS &&\
	grep "linux_amd64.zip" vault_${VAULT_VERSION}_SHA256SUMS | sha256sum -sc &&\
	unzip -q -o vault_${VAULT_VERSION}_linux_amd64.zip -d /usr/local/bin/ &&\
	setcap 'cap_ipc_lock=+ep' /usr/local/bin/vault &&\
# Create Vault user & group and add root to the vault group
	addgroup -S vault &&\
	adduser -H -h /tmp -D -S -G vault -g 'Vault user' -s /dev/null -D vault &&\
	adduser vault consul &&\
	adduser root vault &&\
# Cleanup
	apk -q --no-cache del --purge ca-certificates gnupg wget &&\
	rm -rf vault_${VAULT_VERSION}_* bifurcate_${BIFURCATE_VERSION}_linux_amd64.tar.gz /root/.gnupg

# Copy binaries. bin directory contains start_vault.sh vault-health.sh and consul-cli
COPY bin/ /usr/local/bin
# Copy /etc (Vault config, Bifurcate config)
COPY etc/ /etc
# Copy client certificates
COPY client_certificate.* /etc/tls/

RUN chown -R vault: /etc/vault &&\
	chmod 660 /etc/vault/config.json &&\
	cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt

# Provide your own Vault config file and certificates
ONBUILD COPY config.json /etc/vault/
ONBUILD COPY consul.json /etc/consul/
ONBUILD COPY tls/* /etc/tls/
ONBUILD COPY client_certificate.* /etc/tls/
# Fix permissions & add custom certs to the system certicate store
ONBUILD RUN chown -R vault: /etc/vault &&\
			chmod 660 /etc/vault/config.json &&\
			cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt

# When you build on top of this image, put Consul data on a separate volume to
# avoid filesystem performance issues with Docker image layers
#VOLUME ["/data"]

EXPOSE 8200

ENTRYPOINT ["bifurcate","/etc/bifurcate/bifurcate.json"]
