#!/bin/bash
set -e

OPENRESTY_VERSION=1.11.2.1
OPENSSL_VERSION=1.0.2j
RESTY_LUAROCKS_VERSION=2.3.0
RESTY_PCRE_VERSION=8.39
LUAROCKS_VERSION=2.4.2

HOME_PREFIX=/usr/local
OPENRESTY_DIR=$HOME_PREFIX/openresty
LUAROCKS_DIR=$HOME_PREFIX/luarocks
VAR_PREFIX=/var/nginx
PROFILE_DIR=/etc/profile
TMP=/tmp

OPENRESTY_CONFIGURE_PARAMS=""

mkdir -p $OPENRESTY_DIR
mkdir -p $LUAROCKS_DIR

echo "==> Install perl readline-devel pcre-devel perl-ExtUtils-Embed openssl-devel gcc gcc-c++ git gd-devel GeoIP-devel libxslt-devel musl-dev make unzip zlib-devel libuuid-devel..."
yum install -y perl readline-devel pcre-devel perl-ExtUtils-Embed openssl-devel gcc gcc-c++ git gd-devel GeoIP-devel libxslt-devel musl-dev make unzip zlib-devel libuuid-devel

##########
# Openresty
##########
if [ ! "$(ls -A $OPENRESTY_DIR)" ]; then
	# Download OpenSSL
	echo "==> Downloading OpenSSL..."
	cd $TMP
	OPENSSL_BASE=openssl-$OPENSSL_VERSION
	echo -e "\n\n====================>curl http://www.openssl.org/source/$OPENSSL_BASE.tar.gz<==========================\n\n"
	wget http://www.openssl.org/source/$OPENSSL_BASE.tar.gz
	tar xzf $OPENSSL_BASE.tar.gz
    rm -rf $OPENSSL_BASE.tar.gz
	OPENRESTY_CONFIGURE_PARAMS="--with-openssl=$TMP/openssl-$OPENSSL_VERSION "

	# Download OpenResty
	echo "==> Downloading OpenResty..."
	cd $TMP
	OPENRESTY_BASE=openresty-$OPENRESTY_VERSION
	echo "====================>https://openresty.org/download/$OPENRESTY_BASE.tar.gz -O $OPENRESTY_BASE.tar.gz<=========================="
	wget https://openresty.org/download/$OPENRESTY_BASE.tar.gz
	tar xzf $OPENRESTY_BASE.tar.gz
	rm -rf $TMP/$OPENRESTY_BASE.tar.gz
	#cd $OPENRESTY_BASE
	#cd bundle/nginx-*

	# Get ssl-cert-by-lua branch from github, replace lua-nginx-module and apply patch
	#wget https://github.com/openresty/lua-nginx-module/archive/ssl-cert-by-lua.tar.gz | tar xz
	#patch -p1 < nginx-ssl-cert.patch

	echo "==> Downloading pcre...\n\n"
	wget https://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-${RESTY_PCRE_VERSION}.tar.gz -O pcre-${RESTY_PCRE_VERSION}.tar.gz
	tar xzf pcre-${RESTY_PCRE_VERSION}.tar.gz
	rm -rf $TMP/pcre-${RESTY_PCRE_VERSION}.tar.gz
	OPENRESTY_CONFIGURE_PARAMS=$OPENRESTY_CONFIGURE_PARAMS" --with-pcre=$TMP/pcre-${RESTY_PCRE_VERSION}"

	cd $TMP/$OPENRESTY_BASE

	OPENRESTY_CONFIGURE_PARAMS=$OPENRESTY_CONFIGURE_PARAMS" --prefix=$OPENRESTY_DIR \
	--http-client-body-temp-path=${VAR_PREFIX}/client_body_temp \
    --http-proxy-temp-path=${VAR_PREFIX}/proxy_temp \
    --http-log-path=${VAR_PREFIX}/access.log \
    --error-log-path=${VAR_PREFIX}/error.log \
    --pid-path=${VAR_PREFIX}/nginx.pid \
    --lock-path=${VAR_PREFIX}/nginx.lock \
    --with-luajit=$LUAJIT_DIR \
    --with-openssl=../$OPENSSL_BASE \
    --with-pcre-jit \
    --with-ipv6 \
    --with-http_realip_module \
    --with-http_ssl_module \
    --with-http_stub_status_module
    "

    ./configure --prefix=$OPENRESTY_DIR $OPENRESTY_CONFIGURE_PARAMS
    make
    make install

    # Check nginx install
    echo "==> check up nginx configure..."
	$OPENRESTY_DIR/nginx/sbin/nginx -t
	$OPENRESTY_DIR/nginx/sbin/nginx -V

	##########
	# Luarocks
	##########
	cd $TMP
	echo "==> Installing Luarocks..."
	LUAROCKS_BASE=luarocks-$LUAROCKS_VERSION
	wget http://luarocks.github.io/luarocks/releases/$LUAROCKS_BASE.tar.gz
	tar xzf $LUAROCKS_BASE.tar.gz
	rm -rf $LUAROCKS_BASE.tar.gz
	cd $LUAROCKS_BASE/

	./configure --prefix=$LUAROCKS_DIR \
	--with-lua=$OPENRESTY_DIR/luajit/ \
	--lua-suffix=jit \
	--with-lua-include=$OPENRESTY_DIR/luajit/include/luajit-2.1
	make build
	make install

	cd $TMP
	git clone https://github.com/sumory/lor
	cd lor
	sh install.sh

	echo "==> Installing lua-resty-UUID..."
	cd $TMP
	curl -fSL https://github.com/dcshi/lua-resty-UUID/archive/master.zip -o lua-resty-UUID-master.zip
	unzip lua-resty-UUID-master.zip
	cd lua-resty-UUID-master/clib
	make
	mv libuuidx.so /usr/lib64/libuuidx.so
	yum clean all

	#################################
	# Luarocks lua package dependency
	#################################
	echo "==> Luarocks lua package dependency\n"
	$LUAROCKS_DIR/bin/luarocks install penlight
	$LUAROCKS_DIR/bin/luarocks install md5
	$LUAROCKS_DIR/bin/luarocks install multipart
	$LUAROCKS_DIR/bin/luarocks install luatz
	$LUAROCKS_DIR/bin/luarocks install lua-cmsgpack
	$LUAROCKS_DIR/bin/luarocks install luasocket
	$LUAROCKS_DIR/bin/luarocks install lua-resty-http
	$LUAROCKS_DIR/bin/luarocks install lua-cjson

else
	echo "\n\n====check up you have installed openresty!======\n\n"
fi

############################
# Check openresty luajit bin 
############################
if grep "PATH=.*\/usr\/local\/openresty\/luajit\/bin" $PROFILE_DIR
then
	sed -i_bak 's;\(^PATH=.*\);\1:\/usr\/local\/openresty\/luajit\/bin;g' $PROFILE_DIR
	source $PROFILE_DIR
fi
############################
# Check luarocks bin 
############################
if grep "PATH=.*\/usr\/local\/luarocks\/bin" $PROFILE_DIR
then
	sed -i_bak 's;\(^PATH=.*\);\1:\/usr\/local\/luarocks\/bin;g' $PROFILE_DIR
	source $PROFILE_DIR
fi


################
# Check consul
################
#curl -X PUT -d "" http://127.0.0.1:8500/v1/kv/config/balancer/updated_upstreams
curl -X PUT -d "" http://127.0.0.1:8500/v1/kv/config/balancer/upstreams/