# Vault secure production ready Docker image
[![License ISC](https://img.shields.io/badge/license-ISC-blue.svg)](https://raw.githubusercontent.com/mterron/master/LICENSE) [![](https://images.microbadger.com/badges/image/mterron/vault.svg)](https://microbadger.com/images/mterron/vault "Get your own image badge on microbadger.com") [![](https://images.microbadger.com/badges/commit/mterron/vault.svg)](https://microbadger.com/images/mterron/vault "Get your own commit badge on microbadger.com")
 
[Vault](http://www.vaultproject.io/) in Docker with full TLS security (includes example certificates) and a production ready, hardened example configuration.
Password for the client certificate .p12 bundle is "client".

Uses [bifurcate](https://github.com/novilabs/bifurcate) to handle 2 process (Consul & Vault).
