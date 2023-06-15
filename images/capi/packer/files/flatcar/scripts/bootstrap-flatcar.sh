#!/usr/bin/env bash
#
# This script installs PyPy as a Python interpreter on a Flatcar instance.

set -o errexit
set -o nounset
set -o pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

BINDIR="/opt/bin"
BUILDER_ENV="/opt/bin/builder-env"

set -x

mkdir -p ${BINDIR}

cd ${BINDIR}

if [[ -e ${BINDIR}/.bootstrapped ]]; then
  exit 0
fi

PYPY_HTTP_SOURCE=${PYPY_HTTP_SOURCE:="https://downloads.python.org/pypy"}
PYPY_VERSION=v7.3.11
PYTHON3_VERSION=3.9
PYTHON2_VERSION=2.7

if [[ "$(uname -m)" == "aarch64" ]]; then
  PYPY_ARCH="aarch64"
else
  PYPY_ARCH="linux64"
fi

curl -sfL ${PYPY_HTTP_SOURCE}/pypy${PYTHON2_VERSION}-${PYPY_VERSION}-${PYPY_ARCH}.tar.bz2 | tar -xjf -
mv -n pypy${PYTHON2_VERSION}-${PYPY_VERSION}-${PYPY_ARCH} pypy2
ln -s ./pypy2/bin/pypy python2
${BINDIR}/python2 -m ensurepip

curl -sfL ${PYPY_HTTP_SOURCE}/pypy${PYTHON3_VERSION}-${PYPY_VERSION}-${PYPY_ARCH}.tar.bz2 | tar -xjf -
mv -n pypy${PYTHON3_VERSION}-${PYPY_VERSION}-${PYPY_ARCH} pypy3
ln -s ./pypy3/bin/pypy3 python3
ln -s ./pypy3/bin/pypy3 python

${BINDIR}/python --version
${BINDIR}/python3 -m ensurepip
./pypy3/bin/pip3 install virtualenv

${BINDIR}/pypy3/bin/virtualenv ${BUILDER_ENV}
chown -R core ${BUILDER_ENV}

ln -s builder-env/bin/pip ${BINDIR}/pip
# need to have symlink pip3 required by ansible/roles/providers/tasks/aws.yml
ln -s builder-env/bin/pip ${BINDIR}/pip3

touch ${BINDIR}/.bootstrapped
