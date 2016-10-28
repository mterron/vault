disable_mlock = false
#disable_cache = false
#default_lease_ttl = "30d"
#max_lease_ttl = "30d"

backend "consul" {
	address = "unix:///data/consul.http.sock"
	path = "vault/"
	#datacenter = ""
	#token = ""
	#service = ""
	#tls_cert_file = "/etc/tls/client.certificate.pem"
	#tls_key_file = "/etc/tls/client.certificate.key"
	#tls_ca_file = "/etc/tls/ca.pem"
}

listener "tcp" {
	address = "0.0.0.0:8200"
	tls_cert_file = "/etc/tls/vault.service.consul.pem"
	tls_key_file = "/etc/tls/vault.service.consul.key"
}

#telemetry {
#	statsite_address = "statsite.service.consul:8125"
#	statsd_address = "statsd.service.consul:8125"
#	#disable_hostname = false
#}
