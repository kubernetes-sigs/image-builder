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

PYPY_VERSION=7.2.0
PYTHON3_VERSION=3.6

curl -sfL https://github.com/squeaky-pl/portable-pypy/releases/download/pypy-${PYPY_VERSION}/pypy-${PYPY_VERSION}-linux_x86_64-portable.tar.bz2 | tar -xjf -
mv -n pypy-${PYPY_VERSION}-linux_x86_64-portable pypy2
ln -s ./pypy2/bin/pypy python2
ln -s ./pypy2/bin/pypy python

curl -sfL  https://github.com/squeaky-pl/portable-pypy/releases/download/pypy${PYTHON3_VERSION}-${PYPY_VERSION}/pypy${PYTHON3_VERSION}-${PYPY_VERSION}-linux_x86_64-portable.tar.bz2 | tar -xjf -
mv -n pypy${PYTHON3_VERSION}-${PYPY_VERSION}-linux_x86_64-portable pypy3
ln -s ./pypy3/bin/pypy3 python3

${BINDIR}/python --version

${BINDIR}/pypy2/bin/virtualenv-pypy ${BUILDER_ENV}
chown -R core ${BUILDER_ENV}

ln -s builder-env/bin/pip ${BINDIR}/pip
# need to have symlink pip3 required by ansible/roles/providers/tasks/aws.yml
ln -s builder-env/bin/pip ${BINDIR}/pip3

touch ${BINDIR}/.bootstrapped
