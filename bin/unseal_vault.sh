#!/bin/ash
VAULT_ADDR="https://${HOSTNAME}.node.${CONSUL_DOMAIN:-consul}:8200" vault unseal

