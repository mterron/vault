#!/bin/sh
printf "Fixing Vault dir permissions"
su-exec consul chmod -f g+w /data
chown -fR vault /home/vault /etc/vault 2>/dev/null || true