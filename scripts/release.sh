#!/bin/bash
set -x

NAME=$(basename $(git remote get-url origin | sed 's/\.git//'))
GITHUB_USER=$(basename $(dirname $(git remote get-url origin | sed 's/\.git//')))
GITHUB_USER=${GITHUB_USER##*:}
TAG=$(git tag --points-at HEAD )
if [[ "$TAG" == "" ]];  then
  echo "Skipping release of untagged commit"
  exit 0
fi

if ! which goreleaser 2>&1 > /dev/null; then
  # pin the version to ensure reliable and consistent builders
  wget -nv https://github.com/goreleaser/goreleaser/releases/download/v0.108.0/goreleaser_amd64.deb
  sudo dpkg -i goreleaser_amd64.deb
fi

if ! which rpmbuild 2>&1 > /dev/null; then
  # needed by goreleaser to create rpm's
  sudo apt-get install -y rpm
fi

if ! which upx 2>&1 > /dev/null; then
  sudo apt-get install -y upx-ucl
fi

git stash
git clean -fd
goreleaser --rm-dist

GO111MODULE=off go get github.com/aktau/github-release
go get github.com/aktau/github-release
# compress binaries
upx dist/linux_amd64/${NAME}
upx dist/darwin_amd64/${NAME}
upx dist/windows_amd64/${NAME}.exe

# upload bare, unarchived binaries suitable for direct download in scripts
github-release upload -u $GITHUB_USER -r ${NAME} --tag $TAG -n ${NAME} -f dist/linux_amd64/${NAME}
github-release upload -u $GITHUB_USER -r ${NAME} --tag $TAG -n ${NAME}_osx -f dist/darwin_amd64/${NAME}
github-release upload -u $GITHUB_USER -r ${NAME} --tag $TAG -n ${NAME}.exe -f dist/windows_amd64/${NAME}.exe
