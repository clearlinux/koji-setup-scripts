#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

KOJI_USER="$1"
CERT_SUBJECT="$2"

openssl genrsa -out private/"$KOJI_USER".key 2048
if [ -z "$CERT_SUBJECT" ]; then
	openssl req -config ssl.cnf -new -nodes -out certs/"$KOJI_USER".csr -key private/"$KOJI_USER".key
else
	openssl req -subj "$CERT_SUBJECT" -config ssl.cnf -new -nodes -out certs/"$KOJI_USER".csr -key private/"$KOJI_USER".key
fi
openssl ca -batch -config ssl.cnf -keyfile private/koji_ca_cert.key -cert koji_ca_cert.crt -out certs/"$KOJI_USER".crt -outdir certs -infiles certs/"$KOJI_USER".csr
cat certs/"$KOJI_USER".crt private/"$KOJI_USER".key > "$KOJI_USER".pem
# Browser certificate is not password-protected, ask users to change their password
openssl pkcs12 -export -inkey private/"$KOJI_USER".key -in certs/"$KOJI_USER".crt -CAfile koji_ca_cert.crt -out certs/"$KOJI_USER"_browser_cert.p12 -passout pass:
