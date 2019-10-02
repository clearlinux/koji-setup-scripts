#!/bin/bash
# Copyright (C) 2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

set -xe
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR"/globals.sh
source "$SCRIPT_DIR"/parameters.sh

swupd bundle-add scm-server || :
check_dependency gitolite
check_dependency git

## GITOLITE SETUP
mkdir -p "$GIT_DIR"
chown -R "$GIT_USER":"$GIT_USER" "$GIT_DIR"
# Add symlink for backwards compatibility
if [[ "$GIT_DIR" != "$GIT_DEFAULT_DIR" ]]; then
	if [ "$(ls -A "$GIT_DEFAULT_DIR")" ]; then
		mv "$GIT_DEFAULT_DIR" "$GIT_DEFAULT_DIR".old
	else
		rm -rf "$GIT_DEFAULT_DIR"
	fi
	ln -sf "$GIT_DIR" "$GIT_DEFAULT_DIR"
	chown -h "$GIT_USER":"$GIT_USER" "$GIT_DEFAULT_DIR"
fi
GITOLITE_PUB_KEY_FILE="$GIT_DEFAULT_DIR/gitolite.pub"
echo "$GITOLITE_PUB_KEY" > "$GITOLITE_PUB_KEY_FILE"
chown "$GIT_USER":"$GIT_USER" "$GITOLITE_PUB_KEY_FILE"
sudo -u "$GIT_USER" gitolite setup -pk "$GITOLITE_PUB_KEY_FILE"
usermod -s /bin/bash gitolite

if $IS_ANONYMOUS_GIT_NEEDED; then
	swupd bundle-add httpd || :
	check_dependency httpd

	## GIT PROTOCOL CLONING
	mkdir -p /etc/systemd/system
	cat > /etc/systemd/system/git-daemon.service <<- EOF
	[Unit]
	Description=Git Daemon

	[Service]
	ExecStart=/usr/bin/git daemon --export-all --reuseaddr --base-path=$GIT_DEFAULT_DIR/repositories $GIT_DEFAULT_DIR/repositories

	Restart=always
	RestartSec=500ms

	User=$GIT_USER
	Group=$GIT_USER

	[Install]
	WantedBy=multi-user.target
	EOF
	systemctl daemon-reload
	systemctl enable --now git-daemon


	## CGIT WEB INTERFACE
	cat > /etc/cgitrc <<- EOF
	# Enable caching of up to 1000 output entries
	cache-size=10

	# Specify the css url
	css=/cgit-data/cgit.css

	# Show extra links for each repository on the index page
	enable-index-links=1

	# Enable ASCII art commit history graph on the log pages
	enable-commit-graph=1

	# Show number of affected files per commit on the log pages
	enable-log-filecount=1

	# Show number of added/removed lines per commit on the log pages
	enable-log-linecount=1

	# Use a custom logo
	logo=/cgit-data/cgit.png

	# Enable statistics per week, month and quarter
	max-stats=quarter

	# Allow download of tar.gz, tar.bz2, and tar.xz formats
	snapshots=tar.gz tar.bz2 tar.xz

	##
	## List of common mimetypes
	##
	mimetype.gif=image/gif
	mimetype.html=text/html
	mimetype.jpg=image/jpeg
	mimetype.jpeg=image/jpeg
	mimetype.pdf=application/pdf
	mimetype.png=image/png
	mimetype.svg=image/svg+xml

	# Enable syntax highlighting and about formatting
	source-filter=/usr/libexec/cgit/filters/syntax-highlighting.py
	about-filter=/usr/libexec/cgit/filters/about-formatting.sh

	##
	## List of common readmes
	##
	readme=:README.md
	readme=:readme.md
	readme=:README.mkd
	readme=:readme.mkd
	readme=:README.rst
	readme=:readme.rst
	readme=:README.html
	readme=:readme.html
	readme=:README.htm
	readme=:readme.htm
	readme=:README.txt
	readme=:readme.txt
	readme=:README
	readme=:readme
	readme=:INSTALL.md
	readme=:install.md
	readme=:INSTALL.mkd
	readme=:install.mkd
	readme=:INSTALL.rst
	readme=:install.rst
	readme=:INSTALL.html
	readme=:install.html
	readme=:INSTALL.htm
	readme=:install.htm
	readme=:INSTALL.txt
	readme=:install.txt
	readme=:INSTALL
	readme=:install

	# Direct cgit to repository location managed by gitolite
	remove-suffix=1
	project-list=$GIT_DEFAULT_DIR/projects.list
	scan-path=$GIT_DEFAULT_DIR/repositories
	EOF

	mkdir -p /etc/httpd/conf.modules.d
	cat > /etc/httpd/conf.modules.d/cgid.conf <<- EOF
	LoadModule cgid_module lib/httpd/modules/mod_cgid.so
	ScriptSock /run/httpd/cgid.sock
	EOF

	mkdir -p /etc/httpd/conf.d
	cat > /etc/httpd/conf.d/cgit.conf <<- EOF
	Alias /cgit-data /usr/share/cgit
	<Directory "/usr/share/cgit">
	    AllowOverride None
	    Options None
	    Require all granted
	</Directory>

	ScriptAlias /cgit /usr/libexec/cgit/cgi-bin/cgit
	<Directory "/usr/libexec/cgit">
	    AllowOverride None
	    Options ExecCGI
	    Require all granted
	</Directory>
	EOF
	usermod -a -G "$GIT_USER" "$HTTPD_USER"

	systemctl restart httpd
	systemctl enable httpd
fi
