#!/bin/sh

VERSION=$1
URL=$2

wget $URL
tar xzf sqlite-autoconf-$VERSION.tar.gz

cd sqlite-autoconf-$VERSION
./configure
make
