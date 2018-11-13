#!/usr/bin/env bash
# Copyright (c) 2018 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -xe
SCRIPT_DIR=$(dirname $(realpath "$0"))
source "$SCRIPT_DIR"/parameters.sh

## INSTALL KOJI
swupd bundle-add koji || true

## SETTING UP SSL CERTIFICATES FOR AUTHENTICATION
KOJI_PKI_DIR=/etc/pki/koji
mkdir -p "$KOJI_PKI_DIR"/{certs,private}

# Certificate generation
cat > "$KOJI_PKI_DIR"/ssl.cnf <<- EOF
HOME                    = $KOJI_PKI_DIR
RANDFILE                = $KOJI_PKI_DIR/.rand

[ca]
default_ca              = ca_default

[ca_default]
dir                     = $KOJI_PKI_DIR
certs                   = \$dir/certs
crl_dir                 = \$dir/crl
database                = \$dir/index.txt
new_certs_dir           = \$dir/newcerts
certificate             = \$dir/%s_ca_cert.pem
private_key             = \$dir/private/%s_ca_key.pem
serial                  = \$dir/serial
crl                     = \$dir/crl.pem
x509_extensions         = usr_cert
name_opt                = ca_default
cert_opt                = ca_default
default_days            = 3650
default_crl_days        = 30
default_md              = sha256
preserve                = no
policy                  = policy_match

[policy_match]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[req]
default_bits            = 1024
default_keyfile         = privkey.pem
default_md              = sha256
distinguished_name      = req_distinguished_name
attributes              = req_attributes
x509_extensions         = v3_ca # The extensions to add to the self signed cert
string_mask             = MASK:0x2002

[req_distinguished_name]
countryName                     = Country Name (2 letter code)
countryName_min                 = 2
countryName_max                 = 2
stateOrProvinceName             = State or Province Name (full name)
localityName                    = Locality Name (eg, city)
0.organizationName              = Organization Name (eg, company)
organizationalUnitName          = Organizational Unit Name (eg, section)
commonName                      = Common Name (eg, your name or your server\'s hostname)
commonName_max                  = 64
emailAddress                    = Email Address
emailAddress_max                = 64

[req_attributes]
challengePassword               = A challenge password
challengePassword_min           = 4
challengePassword_max           = 20
unstructuredName                = An optional company name

[usr_cert]
basicConstraints                = CA:FALSE
nsComment                       = "OpenSSL Generated Certificate"
subjectKeyIdentifier            = hash
authorityKeyIdentifier          = keyid,issuer:always

[v3_ca]
subjectKeyIdentifier            = hash
authorityKeyIdentifier          = keyid:always,issuer:always
basicConstraints                = CA:true
EOF

# Generate CA
touch "$KOJI_PKI_DIR"/index.txt
echo 01 > "$KOJI_PKI_DIR"/serial
openssl genrsa -out "$KOJI_PKI_DIR"/private/koji_ca_cert.key 2048
openssl req -subj "/C=$COUNTRY_CODE/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/OU=koji_ca/CN=$KOJI_MASTER_FQDN" -config "$KOJI_PKI_DIR"/ssl.cnf -new -x509 -days 3650 -key "$KOJI_PKI_DIR"/private/koji_ca_cert.key -out "$KOJI_PKI_DIR"/koji_ca_cert.crt -extensions v3_ca
mkdir -p /etc/ca-certs/trusted
cp -a "$KOJI_PKI_DIR"/koji_ca_cert.crt /etc/ca-certs/trusted
clrtrust generate

# Generate the koji component certificates and the admin certificate and generate a PKCS12 user certificate (for web browser)
cp "$SCRIPT_DIR"/gencert.sh "$KOJI_PKI_DIR"
pushd "$KOJI_PKI_DIR"
./gencert.sh kojiweb "/C=$COUNTRY_CODE/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/OU=kojiweb/CN=$KOJI_MASTER_FQDN"
./gencert.sh kojihub "/C=$COUNTRY_CODE/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/OU=kojihub/CN=$KOJI_MASTER_FQDN"
./gencert.sh kojiadmin "/C=$COUNTRY_CODE/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/OU=$ORG_UNIT/CN=kojiadmin"
./gencert.sh kojira "/C=$COUNTRY_CODE/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/OU=$ORG_UNIT/CN=kojira"
popd

# Copy certificates into ~/.koji for kojiadmin
useradd kojiadmin
ADMIN_CERT_DIR=$(getent passwd kojiadmin | cut -d ':' -f 6)/.koji
mkdir -p "$ADMIN_CERT_DIR"
cp -f "$KOJI_PKI_DIR"/kojiadmin.pem "$ADMIN_CERT_DIR"/client.crt
cp -f "$KOJI_PKI_DIR"/koji_ca_cert.crt "$ADMIN_CERT_DIR"/clientca.crt
cp -f "$KOJI_PKI_DIR"/koji_ca_cert.crt "$ADMIN_CERT_DIR"/serverca.crt
chown -R kojiadmin:kojiadmin "$ADMIN_CERT_DIR"


## POSTGRESQL SERVER
# Initialize PostgreSQL DB
mkdir -p /var/lib/pgsql
chown -R postgres:postgres /var/lib/pgsql
sudo -u postgres initdb --pgdata /var/lib/pgsql/data
systemctl enable --now postgresql

# Setup User Accounts
useradd -r koji

# Setup PostgreSQL and populate schema
sudo -u postgres createuser --no-superuser --no-createrole --no-createdb koji
sudo -u postgres createdb -O koji koji
sudo -u koji psql koji koji < /usr/share/doc/koji*/docs/schema.sql

# Authorize Koji-web and Koji-hub resources
# TODO: Add authentication with SSL certificates
cat > /var/lib/pgsql/data/pg_hba.conf <<- EOF
#TYPE   DATABASE    USER    CIDR-ADDRESS      METHOD
host    koji        all    127.0.0.1/32       trust
host    koji        all    ::1/128            trust
local   koji        all                       trust
EOF

# Bootstrapping the initial koji admin user into the PostgreSQL database
# SSL Certificate authentication
sudo -u koji psql -c "insert into users (name, status, usertype) values ('kojiadmin', 0, 0);"

# Give yourself admin permissions
sudo -u koji psql -c "insert into user_perms (user_id, perm_id, creator_id) values (1, 1, 1);"


## KOJI CONFIGURATION FILES
# Koji Hub
mkdir -p /etc/koji-hub
cat > /etc/koji-hub/hub.conf <<- EOF
[hub]
DBName = koji
DBUser = koji
KojiDir = $KOJI_DIR
DNUsernameComponent = CN
ProxyDNs = C=$COUNTRY_CODE,ST=$STATE,L=$LOCATION,O=$ORGANIZATION,OU=kojiweb,CN=$KOJI_MASTER_FQDN
LoginCreatesUser = On
KojiWebURL = https://$KOJI_MASTER_FQDN/koji
DisableNotifications = True
EOF

# Koji Web
mkdir -p /etc/kojiweb
cat > /etc/kojiweb/web.conf <<- EOF
[web]
SiteName = koji
KojiHubURL = https://$KOJI_MASTER_FQDN/kojihub
KojiFilesURL = https://$KOJI_MASTER_FQDN/kojifiles
WebCert = $KOJI_PKI_DIR/kojiweb.pem
ClientCA = $KOJI_PKI_DIR/koji_ca_cert.crt
KojiHubCA = $KOJI_PKI_DIR/koji_ca_cert.crt
LoginTimeout = 72
Secret = NITRA_IS_NOT_CLEAR
LibPath = /usr/share/koji-web/lib
LiteralFooter = True
EOF

# Koji CLI
cat > /etc/koji.conf <<- EOF
[koji]
server = https://$KOJI_MASTER_FQDN/kojihub
weburl = https://$KOJI_MASTER_FQDN/koji
topurl = https://$KOJI_MASTER_FQDN/kojifiles
topdir = $KOJI_DIR
cert = ~/.koji/client.crt
ca = ~/.koji/clientca.crt
serverca = ~/.koji/serverca.crt
anon_retry = true
EOF


## KOJI APPLICATION HOSTING
# Koji Filesystem Skeleton
mkdir -p "$KOJI_DIR"/{packages,repos,work,scratch,repos-dist}
chown -R httpd:httpd "$KOJI_DIR"

## Apache Configuration Files
mkdir -p /etc/httpd/conf.d
cat > /etc/httpd/conf.d/koji.conf <<- EOF
LoadModule ssl_module lib/httpd/modules/mod_ssl.so

<VirtualHost _default_:80>
    AllowEncodedSlashes NoDecode
    RedirectMatch permanent /(.*) https://$KOJI_MASTER_FQDN/$1
</VirtualHost>

Listen 443
<VirtualHost _default_:443>
    ServerName $KOJI_MASTER_FQDN

    SSLEngine on
    SSLProtocol -all +TLSv1.2
    SSLCipherSuite EECDH+ECDSA+AESGCM:EECDH+aRSA+AESGCM:EECDH+ECDSA+SHA384:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA384:EECDH+aRSA+SHA256:EECDH:EDH+aRSA:HIGH:!aNULL:!eNULL:!LOW:!3DES:!MD5:!EXP:!PSK:!SRP:!DSS:!RC4:!DH:!SHA1
    SSLHonorCipherOrder on
    SSLOptions +StrictRequire +StdEnvVars

    SSLCertificateFile $KOJI_PKI_DIR/kojihub.pem
    SSLCertificateKeyFile $KOJI_PKI_DIR/private/kojihub.key
    SSLCertificateChainFile $KOJI_PKI_DIR/koji_ca_cert.crt
    SSLCACertificateFile $KOJI_PKI_DIR/koji_ca_cert.crt
    SSLVerifyClient optional
    SSLVerifyDepth 10

    # Koji Hub
    Alias /kojihub /usr/share/koji-hub/kojixmlrpc.py
    <Directory "/usr/share/koji-hub">
        Options ExecCGI
        SetHandler wsgi-script
        Require all granted
    </Directory>
    Alias /kojifiles "/srv/koji/"
    <Directory "/srv/koji">
        Options Indexes SymLinksIfOwnerMatch
        AllowOverride None
        Require all granted
    </Directory>
    <Location /kojihub/ssllogin>
        SSLVerifyClient require
    </Location>

    # Koji Web
    Alias /koji "/usr/share/koji-web/scripts/wsgi_publisher.py"
    <Directory "/usr/share/koji-web/scripts/">
        Options ExecCGI
        SetHandler wsgi-script
        Require all granted
    </Directory>
    Alias /koji-static/ "/usr/share/koji-web/static/"
    <Directory "/usr/share/koji-web/static/">
        Options None
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF

## Apache Configuration Files
mkdir -p /etc/httpd/conf.modules.d
cat > /etc/httpd/conf.modules.d/wsgi.conf <<- EOF
LoadModule wsgi_module lib/python2.7/site-packages/mod_wsgi/server/mod_wsgi-py27.so
WSGISocketPrefix /run/httpd/wsgi
EOF

systemctl enable --now httpd


## TEST KOJI CONNECTIVITY
sudo -u kojiadmin koji moshimoshi


## KOJI DAEMON - BUILDER
# Add the host entry for the koji builder to the database
sudo -u kojiadmin koji add-host "$KOJI_SLAVE_FQDN" i386 x86_64

# Add the host to the createrepo channel
sudo -u kojiadmin koji add-host-to-channel "$KOJI_SLAVE_FQDN" createrepo

# A note on capacity
sudo -u kojiadmin koji edit-host --capacity="$KOJID_CAPACITY" "$KOJI_SLAVE_FQDN"

# Generate certificates
pushd "$KOJI_PKI_DIR"
./gencert.sh "$KOJI_SLAVE_FQDN" "/C=$COUNTRY_CODE/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/CN=$KOJI_SLAVE_FQDN"
popd

# Create mock folders and permissions
mkdir -p /etc/mock/koji
mkdir -p /var/lib/mock
chown -R root:mock /var/lib/mock

# Setup User Accounts
useradd -r kojibuilder
usermod -G mock kojibuilder

# Kojid Configuration Files
mkdir -p /etc/kojid
cat > /etc/kojid/kojid.conf <<- EOF
[kojid]
sleeptime=5
maxjobs=16
topdir=$KOJI_DIR
workdir=/tmp/koji
mockdir=/var/lib/mock
mockuser=kojibuilder
mockhost=generic-linux-gnu
user=$KOJI_SLAVE_FQDN
server=https://$KOJI_MASTER_FQDN/kojihub
topurl=https://$KOJI_MASTER_FQDN/kojifiles
use_createrepo_c=True
allowed_scms=$CGIT_FQDN:/packages/*
cert = $KOJI_PKI_DIR/$KOJI_SLAVE_FQDN.pem
ca = $KOJI_PKI_DIR/koji_ca_cert.crt
serverca = $KOJI_PKI_DIR/koji_ca_cert.crt
EOF

if env | grep -q proxy; then
	echo "yum_proxy = $https_proxy" >> /etc/kojid/kojid.conf
	mkdir -p /etc/systemd/system/kojid.service.d
	cat > /etc/systemd/system/kojid.service.d/00-proxy.conf <<- EOF
	[Service]
	Environment=http_proxy=$http_proxy
	Environment=https_proxy=$https_proxy
	Environment=no_proxy=$no_proxy
	EOF
	systemctl daemon-reload
fi

systemctl enable --now kojid


## KOJIRA - DNF|YUM REPOSITORY CREATION AND MAINTENANCE
# Add the user entry for the kojira user
sudo -u kojiadmin koji add-user kojira
sudo -u kojiadmin koji grant-permission repo kojira

# Kojira Configuration Files
mkdir -p /etc/kojira
cat > /etc/kojira/kojira.conf <<- EOF
[kojira]
server=https://$KOJI_MASTER_FQDN/kojihub
topdir=$KOJI_DIR
logfile=/var/log/kojira.log
with_src=no
cert = $KOJI_PKI_DIR/kojira.pem
ca = $KOJI_PKI_DIR/koji_ca_cert.crt
serverca = $KOJI_PKI_DIR/koji_ca_cert.crt
EOF

systemctl enable --now kojira
