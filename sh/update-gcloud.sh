#! /bin/bash
#  upgrade CircleCI builtin gcloud tools, and set it up
#
# The following ENV vars must be set before calling this script:
#
#   CLOUDSDK_CORE_PROJECT  # Google Cloud project Id to deploy into
#   GCLOUD_EMAIL           # user-id for circle to authenticate to google cloud
#   GCLOUD_KEY             # base64 encoded key
#   CLOUDSDK_COMPUTE_ZONE  # The compute zone container the GKE container cluster to deploy into
#   CLUSTER_ID             # ID of the GKE container cluster to deploy into
set -eou pipefail

if [ "$CIRCLECI" != "true" ]; then
  echo "This script is only intended to run on Circle-CI."
  exit 1
fi

export PATH=$PATH:/opt/google-cloud-sdk/bin
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
export CLOUDSDK_PYTHON_SITEPACKAGES=0

gcloud="/opt/google-cloud-sdk/bin/gcloud"

# ensure we use certs to talk to kube, instead of the oauth bridge (google auth creds)
export CLOUDSDK_CONTAINER_USE_CLIENT_CERTIFICATE=True

sudo -E $gcloud components update > /dev/null 2>&1
sudo -E $gcloud components update kubectl > /dev/null 2>&1

sudo -E chown -R ubuntu /home/ubuntu/.config/gcloud

echo "Setting Project"
$gcloud config set project "$CLOUDSDK_CORE_PROJECT"

echo "Setting Zone"
$gcloud config set compute/zone "$CLOUDSDK_COMPUTE_ZONE"

echo "Setting Cluster"
$gcloud config set container/cluster "$CLUSTER_ID"

echo "$GCLOUD_KEY" | base64 --decode > gcloud.json
$gcloud auth activate-service-account "$GCLOUD_EMAIL" --key-file gcloud.json

sshkey="$HOME/.ssh/google_compute_engine"
if [ ! -f "$sshkey" ] ; then
  ssh-keygen -f "$sshkey" -N ""
fi

#echo "Setting up default credentials"
#$gcloud auth application-default login

$gcloud container clusters get-credentials "$CLUSTER_ID" --project="$CLOUDSDK_CORE_PROJECT"  > /dev/null
