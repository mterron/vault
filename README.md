# Vault secure production ready Docker image
[![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://raw.githubusercontent.com/mterron/master/LICENSE)
 
[Vault](http://www.vaultproject.io/) in Docker with full TLS security (includes example certificates) and a production ready, hardened example configuration.
Password for the client certificate .p12 bundle is "client".

Uses [bifurcate](https://github.com/novilabs/bifurcate) to handle 2 process (Consul & Vault).


This project builds on the fine examples set by the [AutoPilot](http://autopilotpattern.io) pattern team. It also, obviously, wouldn't be possible without the outstanding work of the [Hashicorp team](https://hashicorp.com) that made [Consul](https://www.consul.io) and [Vault](https://www.vaultproject.io) and [NoviLabs](http://www.novilabs.com) creators of [Bifurcate](https://github.com/novilabs/bifurcate).
