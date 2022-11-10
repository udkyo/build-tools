#!/bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

cd ${SCRIPTPATH}/output/${PRODUCT}-${VERSION}/src
source ./escrow_config
rm -rf *.deb \
       *.tar.gz \
       .repo \
       server_build
cd ..
tar -czvf ${PRODUCT}-${VERSION}.tar.gz ${PRODUCT}-${VERSION}
