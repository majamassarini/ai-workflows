#!/bin/bash

# Try starting CRC with monitoring disabled (sometimes helps)
# crc start --memory 16384 --cpus 6 --disable-update-check

# Run this script as kubeadmin
# oc login -u kubeadmin -p $PASSWORD https://api.crc.testing:6443

# Disable the OpenShift sample cluster manager - this is not needed for production and isn't starting up
oc patch config.samples.operator.openshift.io/cluster --type='merge' -p='{
  "spec": {
    "managementState": "Removed"
  }
}'

# Create the project
oc new-project jotnar-prod

# Create the secret for the MCP
sh -x ./create-mcp-atlassian-secret.sh

# Get the registry external URL - you need to be administrator
REGISTRY_URL=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')

# Login with your OpenShift token
podman login --tls-verify=false -u $(oc whoami) -p $(oc whoami -t) $REGISTRY_URL

# Tag your local images and push to the internal registry
podman tag docker.io/valkey/valkey:8 $REGISTRY_URL/jotnar-prod/valkey:prod
podman tag jira-issue-fetcher:latest $REGISTRY_URL/jotnar-prod/jira-issue-fetcher:prod
podman tag docker.io/joeferner/redis-commander:0.9.0 $REGISTRY_URL/jotnar-prod/redis-commander:prod

# Push to OpenShift registry
podman push --tls-verify=false $REGISTRY_URL/jotnar-prod/valkey:prod
podman push --tls-verify=false $REGISTRY_URL/jotnar-prod/jira-issue-fetcher:prod
podman push --tls-verify=false $REGISTRY_URL/jotnar-prod/redis-commander:prod

sh -x ./deploy.sh
