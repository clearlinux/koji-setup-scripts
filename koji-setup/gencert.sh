#!/bin/bash
# user is equal to parameter one or the first argument when you actually
# run the script
user=$1
# subject is equal to parameter two or the second argument when you actually
# run the script
subject="$2"

openssl genrsa -out private/${user}.key 2048
if [ -z "$subject" ]; then
	openssl req -config ssl.cnf -new -nodes -out certs/${user}.csr -key private/${user}.key
else
	openssl req -subj "$subject" -config ssl.cnf -new -nodes -out certs/${user}.csr -key private/${user}.key
fi
openssl ca -batch -config ssl.cnf -keyfile private/koji_ca_cert.key -cert koji_ca_cert.crt -out certs/${user}.crt -outdir certs -infiles certs/${user}.csr
cat certs/${user}.crt private/${user}.key > ${user}.pem
openssl pkcs12 -export -inkey private/${user}.key -in certs/${user}.crt -CAfile koji_ca_cert.crt -out certs/${user}_browser_cert.p12 -passout pass:
