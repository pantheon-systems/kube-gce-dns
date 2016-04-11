#! /bin/bash
# install and configure gcloud on circle-ci
#
# The following ENV vars must be set before calling this script:
#
#   CLOUDSDK_CORE_PROJECT  # Google Cloud project Id to deploy into
#   GCLOUD_EMAIL           # user-id for circle to authenticate to google cloud
#   GCLOUD_KEY             # base64 encoded key
#   CLOUDSDK_COMPUTE_ZONE  # The compute zone container the GKE container cluster to deploy into
#   CLUSTER_ID             # ID of the GKE container cluster to deploy into

set -e

if [ "$CIRCLECI" != "true" ]; then
  echo "This script is only intended to run on Circle-CI."
  exit 1
fi

export CLOUDSDK_CORE_DISABLE_PROMPTS=1
export CLOUDSDK_PYTHON_SITEPACKAGES=0

gcloud="$HOME/google-cloud-sdk/bin/gcloud"
PATH="$gcloud/bin:$PATH"

if [ ! -d "$HOME/google-cloud-sdk" ]; then
  echo "$HOME/gogole-cloud-sdk missing, installing"
  pip install pyopenssl

  curl -o "$HOME/google-cloud-sdk.tar.gz" https://dl.google.com/dl/cloudsdk/channels/rapid/google-cloud-sdk.tar.gz
  tar -C "$HOME/" -xzvf ~/google-cloud-sdk.tar.gz
  bash "$HOME/google-cloud-sdk/install.sh"

  $gcloud components update
  $gcloud components update kubectl
fi

$gcloud config set project $CLOUDSDK_CORE_PROJECT
$gcloud config set compute/zone $CLOUDSDK_COMPUTE_ZONE
$gcloud config set container/cluster $CLUSTER_ID


echo $GCLOUD_KEY | base64 --decode > gcloud.json
$gcloud auth activate-service-account $GCLOUD_EMAIL --key-file gcloud.json

sshkey="$HOME/.ssh/google_compute_engine"
if [ ! -f "$sshkey" ] ; then
  ssh-keygen -f $sshkey -N ""
fi

$gcloud container clusters get-credentials "$CLUSTER_ID" --project="$CLOUDSDK_CORE_PROJECT"
