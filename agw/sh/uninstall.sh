#!/bin/bash
set -e

read -p "Are you sure uninstall ? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
	OPENRESTY_VERSION=1.11.2.1
	OPENSSL_VERSION=fips-2.0.14
	RESTY_LUAROCKS_VERSION=2.3.0
	RESTY_PCRE_VERSION=8.39
	LUAROCKS_VERSION=2.2.2

	HOME_PREFIX=/usr/local
	OPENRESTY_DIR=$HOME_PREFIX/openresty
	LUAROCKS_DIR=$HOME_PREFIX/luarocks
	VAR_PREFIX=/var/nginx
	TMP=/tmp

	rm -rf $OPENRESTY_DIR
	rm -rf $LUAROCKS_DIR
	rm -rf $VAR_PREFIX
	rm -rf $TMP/openresty*
	rm -rf $TMP/pcre-$RESTY_PCRE_VERSION
	rm -rf $TMP/openssl-$OPENSSL_VERSION
	rm -rf $HOME_PREFIX/lor
	rm -rf $TMP/openresty-$OPENRESTY_VERSION
	rm -rf $TMP/openssl-$OPENSSL_VERSION
else
    exit 1
fi