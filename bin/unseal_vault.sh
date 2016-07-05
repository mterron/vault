#!/bin/ash
VAULT_ADDR="https://$(hostname -s).node.consul:8200" vault unseal
