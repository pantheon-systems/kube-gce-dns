#!/bin/bash
# circleCI specific hacks for making go work normal.
#  set GOVERSION to the version you want installed in your circle.yml, or circle ENV.
#  the script will remove circles Go install, and copy the progject into a GOPATH/src/IMPORTPATH
#  location so your project refrenced imports will work
set -e

if [ "$CIRCLECI" != "true" ]; then
  echo "This script meant to only be run on CIRCLECI"
  exit 1
fi

if [ -z "$GOVERSION" ] ; then
  echo "set GOVERSION environment var"
  exit 1
fi


function fu_circle {
  # convert  CIRCLE_REPOSITORY_URL=https://github.com/user/repo -> github.com/user/repo
  local IMPORT_PATH
  IMPORT_PATH=$(sed -e 's#https://##' <<< "$CIRCLE_REPOSITORY_URL")
  sudo rm -rf /usr/local/go
  sudo rm -rf /home/ubuntu/.go_workspace || true
  sudo ln -s "$HOME/go$GOVERSION"  /usr/local/go
  mkdir -p "$GOPATH/src/$IMPORT_PATH"
  rsync -az --delete ./ "$GOPATH/src/$IMPORT_PATH/"
  pd=$(pwd)
  cd ../
  rm -rf "$pd"
  ln -s "$GOPATH/src/$IMPORT_PATH" "$pd"
}

if [  -d "$HOME/go${GOVERSION}" ] ; then
  echo "go $GOVERSION installed preping go import path"
  fu_circle
  exit 0
fi

gotar=go${GOVERSION}.tar.gz
curl -o "$HOME/$gotar" "https://storage.googleapis.com/golang/go${GOVERSION}.linux-amd64.tar.gz"
tar -C "$HOME/" -xzf "$HOME/$gotar"
mv "$HOME/go" "$HOME/go$GOVERSION"
fu_circle
