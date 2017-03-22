# Vault secure production ready Docker image
[![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://raw.githubusercontent.com/mterron/master/LICENSE)
 
[Vault](http://www.vaultproject.io/) in Docker with full TLS security (includes example certificates) and a production ready, hardened example configuration.
Password for the client certificate .p12 bundle is "client".

Uses [bifurcate](https://github.com/novilabs/bifurcate) to handle 2 process (Consul & Vault).
