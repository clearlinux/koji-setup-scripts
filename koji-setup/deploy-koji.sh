#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR"/globals.sh
source "$SCRIPT_DIR"/parameters.sh

swupd bundle-add koji || :
check_dependency koji
check_dependency httpd
check_dependency kojira
check_dependency postgres

## SETTING UP SSL CERTIFICATES FOR AUTHENTICATION
mkdir -p "$KOJI_PKI_DIR"/{certs,private}
RANDFILE="$KOJI_PKI_DIR"/.rand
dd if=/dev/urandom of="$RANDFILE" bs=256 count=1

# Certificate generation
cat > "$KOJI_PKI_DIR"/ssl.cnf <<- EOF
HOME                    = $KOJI_PKI_DIR
RANDFILE                = $RANDFILE

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
default_md              = sha512
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
default_bits            = 4096
default_keyfile         = privkey.pem
default_md              = sha512
distinguished_name      = req_distinguished_name
attributes              = req_attributes
x509_extensions         = v3_ca # The extensions to add to the self signed cert
string_mask             = MASK:0x2002

[req_distinguished_name]
countryName                     = Country Name (2 letter code)
countryName_min                 = 2
countryName_max                 = 64
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
challengePassword_max           = 128
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

# Generate and trust CA
touch "$KOJI_PKI_DIR"/index.txt
echo 01 > "$KOJI_PKI_DIR"/serial
openssl genrsa -out "$KOJI_PKI_DIR"/private/koji_ca_cert.key 2048
openssl req -subj "/C=$COUNTRY_CODE/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/OU=koji_ca/CN=$KOJI_MASTER_FQDN" -config "$KOJI_PKI_DIR"/ssl.cnf -new -x509 -days 3650 -key "$KOJI_PKI_DIR"/private/koji_ca_cert.key -out "$KOJI_PKI_DIR"/koji_ca_cert.crt -extensions v3_ca
mkdir -p /etc/ca-certs/trusted
cp -a "$KOJI_PKI_DIR"/koji_ca_cert.crt /etc/ca-certs/trusted
while true; do
	if clrtrust generate; then
		break
	fi
done

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
ADMIN_KOJI_DIR="$(echo ~kojiadmin)"/.koji
mkdir -p "$ADMIN_KOJI_DIR"
cp -f "$KOJI_PKI_DIR"/kojiadmin.pem "$ADMIN_KOJI_DIR"/client.crt
cp -f "$KOJI_PKI_DIR"/koji_ca_cert.crt "$ADMIN_KOJI_DIR"/clientca.crt
cp -f "$KOJI_PKI_DIR"/koji_ca_cert.crt "$ADMIN_KOJI_DIR"/serverca.crt
chown -R kojiadmin:kojiadmin "$ADMIN_KOJI_DIR"


## POSTGRESQL SERVER
# Initialize PostgreSQL DB
mkdir -p "$POSTGRES_DIR"
chown -R "$POSTGRES_USER":"$POSTGRES_USER" "$POSTGRES_DIR"
if [[ "$POSTGRES_DIR" != "$POSTGRES_DEFAULT_DIR" ]]; then
	if [ "$(ls -A "$POSTGRES_DEFAULT_DIR")" ]; then
		mv "$POSTGRES_DEFAULT_DIR" "$POSTGRES_DEFAULT_DIR".old
	else
		rm -rf "$POSTGRES_DEFAULT_DIR"
	fi
	ln -sf "$POSTGRES_DIR" "$POSTGRES_DEFAULT_DIR"
	chown -h "$POSTGRES_USER":"$POSTGRES_USER" "$POSTGRES_DEFAULT_DIR"
fi
sudo -u "$POSTGRES_USER" initdb --pgdata "$POSTGRES_DEFAULT_DIR"/data
systemctl enable --now postgresql

# Setup User Accounts
useradd -r koji

# Setup PostgreSQL and populate schema
sudo -u "$POSTGRES_USER" createuser --no-superuser --no-createrole --no-createdb koji
sudo -u "$POSTGRES_USER" createdb -O koji koji
sudo -u koji psql koji koji < /usr/share/doc/koji*/docs/schema.sql

# Authorize Koji-web and Koji-hub resources
cat > "$POSTGRES_DEFAULT_DIR"/data/pg_hba.conf <<- EOF
#TYPE    DATABASE    USER    CIDR-ADDRESS    METHOD
host     koji        all     127.0.0.1/32    trust
host     koji        all     ::1/128         trust
local    koji        all                     trust
EOF
systemctl reload postgresql

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
KojiWebURL = $KOJI_URL/koji
DisableNotifications = True
EOF

mkdir -p /etc/httpd/conf.d
cat > /etc/httpd/conf.d/kojihub.conf <<- EOF
Alias /kojihub /usr/share/koji-hub/kojixmlrpc.py
<Directory "/usr/share/koji-hub">
    Options ExecCGI
    SetHandler wsgi-script
    Require all granted
</Directory>
Alias /kojifiles "$KOJI_DIR"
<Directory "$KOJI_DIR">
    Options Indexes SymLinksIfOwnerMatch
    AllowOverride None
    Require all granted
</Directory>
<Location /kojihub/ssllogin>
    SSLVerifyClient require
    SSLVerifyDepth 10
    SSLOptions +StdEnvVars
</Location>
EOF

# Koji Web
mkdir -p /etc/kojiweb
cat > /etc/kojiweb/web.conf <<- EOF
[web]
SiteName = koji
KojiHubURL = $KOJI_URL/kojihub
KojiFilesURL = $KOJI_URL/kojifiles
WebCert = $KOJI_PKI_DIR/kojiweb.pem
ClientCA = $KOJI_PKI_DIR/koji_ca_cert.crt
KojiHubCA = $KOJI_PKI_DIR/koji_ca_cert.crt
LoginTimeout = 72
Secret = NITRA_IS_NOT_CLEAR
LibPath = /usr/share/koji-web/lib
LiteralFooter = True
EOF

mkdir -p /etc/httpd/conf.d
cat > /etc/httpd/conf.d/kojiweb.conf <<- EOF
Alias /koji "/usr/share/koji-web/scripts/wsgi_publisher.py"
<Directory "/usr/share/koji-web/scripts">
    Options ExecCGI
    SetHandler wsgi-script
    Require all granted
</Directory>
Alias /koji-static "/usr/share/koji-web/static"
<Directory "/usr/share/koji-web/static">
    Options None
    AllowOverride None
    Require all granted
</Directory>
EOF

# Koji CLI
cat > "$ADMIN_KOJI_DIR"/config <<- EOF
[koji]
server = $KOJI_URL/kojihub
weburl = $KOJI_URL/koji
topurl = $KOJI_URL/kojifiles
topdir = $KOJI_DIR
cert = ~/.koji/client.crt
ca = ~/.koji/clientca.crt
serverca = ~/.koji/serverca.crt
anon_retry = true
EOF
chown kojiadmin:kojiadmin "$ADMIN_KOJI_DIR"/config

## KOJI APPLICATION HOSTING
# Koji Filesystem Skeleton
mkdir -p "$KOJI_DIR"/{packages,repos,work,scratch,repos-dist}
chown -R "$HTTPD_USER":"$HTTPD_USER" "$KOJI_DIR"

## Apache Configuration Files
mkdir -p /etc/httpd/conf.d
cat > /etc/httpd/conf.d/ssl.conf <<- EOF
ServerName $KOJI_MASTER_FQDN

Listen 443 https

#SSLPassPhraseDialog exec:/usr/libexec/httpd-ssl-pass-dialog

#SSLSessionCache         shmcb:/run/httpd/sslcache(512000)

SSLRandomSeed startup file:/dev/urandom  256
SSLRandomSeed connect builtin

<VirtualHost _default_:443>
    ErrorLog /var/log/httpd/ssl_error_log
    TransferLog /var/log/httpd/ssl_access_log
    LogLevel warn

    SSLEngine on
    SSLProtocol -all +TLSv1.2
    SSLCipherSuite EECDH+ECDSA+AESGCM:EECDH+aRSA+AESGCM:EECDH+ECDSA+SHA384:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA384:EECDH+aRSA+SHA256:EECDH:EDH+aRSA:HIGH:!aNULL:!eNULL:!LOW:!3DES:!MD5:!EXP:!PSK:!SRP:!DSS:!RC4:!DH:!SHA1
    SSLHonorCipherOrder on

    SSLCertificateFile $KOJI_PKI_DIR/kojihub.pem
    SSLCertificateKeyFile $KOJI_PKI_DIR/private/kojihub.key
    SSLCertificateChainFile $KOJI_PKI_DIR/koji_ca_cert.crt
    SSLCACertificateFile $KOJI_PKI_DIR/koji_ca_cert.crt
    SSLVerifyClient optional
    SSLVerifyDepth 10

    <Files ~ "\.(cgi|shtml|phtml|php3?)$">
        SSLOptions +StdEnvVars
    </Files>
    <Directory "/var/www/cgi-bin">
        SSLOptions +StdEnvVars
    </Directory>

    CustomLog /var/log/httpd/ssl_request_log "%t %h %{SSL_PROTOCOL}x %{SSL_CIPHER}x \"%r\" %b"
</VirtualHost>
EOF

mkdir -p /etc/httpd/conf.modules.d
cat > /etc/httpd/conf.modules.d/wsgi.conf <<- EOF
WSGISocketPrefix /run/httpd/wsgi
EOF
cat > /etc/httpd/conf.modules.d/ssl.conf <<- EOF
LoadModule ssl_module lib/httpd/modules/mod_ssl.so
EOF

systemctl enable --now httpd


## TEST KOJI CONNECTIVITY
sudo -u kojiadmin koji moshimoshi


## KOJI DAEMON - BUILDER
# Add the host entry for the koji builder to the database
sudo -u kojiadmin koji add-host "$KOJI_SLAVE_FQDN" "$RPM_ARCH"

# Add the host to the createrepo channel
sudo -u kojiadmin koji add-host-to-channel "$KOJI_SLAVE_FQDN" createrepo

# A note on capacity
sudo -u kojiadmin koji edit-host --capacity="$KOJID_CAPACITY" "$KOJI_SLAVE_FQDN"

# Generate certificates
pushd "$KOJI_PKI_DIR"
./gencert.sh "$KOJI_SLAVE_FQDN" "/C=$COUNTRY_CODE/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/CN=$KOJI_SLAVE_FQDN"
popd

if [[ "$KOJI_SLAVE_FQDN" = "$KOJI_MASTER_FQDN" ]]; then
	"$SCRIPT_DIR"/deploy-koji-builder.sh
fi


## KOJIRA - DNF|YUM REPOSITORY CREATION AND MAINTENANCE
# Add the user entry for the kojira user
sudo -u kojiadmin koji add-user kojira
sudo -u kojiadmin koji grant-permission repo kojira

# Kojira Configuration Files
mkdir -p /etc/kojira
cat > /etc/kojira/kojira.conf <<- EOF
[kojira]
server=$KOJI_URL/kojihub
topdir=$KOJI_DIR
logfile=/var/log/kojira.log
with_src=no
cert = $KOJI_PKI_DIR/kojira.pem
ca = $KOJI_PKI_DIR/koji_ca_cert.crt
serverca = $KOJI_PKI_DIR/koji_ca_cert.crt
EOF

# Ensure postgresql is started prior to running kojira service
mkdir -p /etc/systemd/system/kojira.service.d
cat > /etc/systemd/system/kojira.service.d/after-postgresql.conf <<EOF
[Unit]
After=postgresql.service
EOF

systemctl enable --now kojira
