#!/bin/sh
cat /etc/tls/ca.pem >> /etc/ssl/certs/ca-certificates.crt
touch /etc/ssl/certs/ca-consul.done