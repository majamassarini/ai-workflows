#!/bin/bash
# Start CRC and deploy Ymir
# Run after setup-existing-vm.sh completes and secrets are copied
#
# Usage: Run this on the VM as root
#   ./start-and-deploy.sh

set -euo pipefail

echo "=========================================="
echo "Starting CRC and Deploying Ymir"
echo "=========================================="
echo ""

# Check secrets exist
if [ ! -f "/root/ai-workflows/.secrets/testing-farm/pull-secret.txt" ]; then
    echo "ERROR: Secrets not found!"
    echo "Please copy secrets first:"
    echo "  scp -r /home/mmassari/forges/github/ai-workflows/.secrets/testing-farm root@<VM-IP>:/root/ai-workflows/.secrets/"
    exit 1
fi

# Get crc user UID for XDG_RUNTIME_DIR
CRC_UID=$(id -u crc)
XDG_RUNTIME_DIR="/run/user/${CRC_UID}"

# Start CRC as crc user
echo "Starting CRC..."
su - crc -c "
    set -eux
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}

    # Start CRC with pull secret
    crc start --pull-secret-file ~/ai-workflows/.secrets/testing-farm/pull-secret.txt

    # Show credentials
    echo ''
    echo '=========================================='
    echo 'CRC Credentials:'
    echo '=========================================='
    crc console --credentials
"

# Prepare OpenShift project and secrets
echo ""
echo "Preparing OpenShift project and secrets..."
su - crc -c '
    set -eux
    cd /home/crc/ai-workflows

    # Configure oc environment
    eval $(crc oc-env)

    # Get kubeadmin password
    CRC_PASS=$(crc console --credentials | grep "Password:" | awk '"'"'{print $2}'"'"')

    # Login to OpenShift
    oc login -u kubeadmin -p "${CRC_PASS}" https://api.crc.testing:6443

    # Create project
    oc new-project jotnar-ymir--jotnar-ymir || oc project jotnar-ymir--jotnar-ymir

    # Create secrets
    echo "Creating OpenShift secrets..."
    oc create secret generic gitlab-env \
        --from-file=GITLAB_TOKEN=.secrets/testing-farm/gitlab-token \
        --dry-run=client -o yaml | oc apply -f -

    oc create secret generic jira-env \
        --from-file=JIRA_TOKEN=.secrets/testing-farm/jira-token \
        --dry-run=client -o yaml | oc apply -f -

    oc create secret generic testing-farm-env \
        --from-file=TESTING_FARM_API_TOKEN=.secrets/testing-farm/testing-farm-internal-token \
        --dry-run=client -o yaml | oc apply -f -

    oc create secret generic sentry-env \
        --from-file=SENTRY_DSN=.secrets/testing-farm/sentry-dsn \
        --dry-run=client -o yaml | oc apply -f -

    oc create secret generic vertex-key \
        --from-file=jotnar-vertex-prod.json=.secrets/testing-farm/vertex-key.json \
        --dry-run=client -o yaml | oc apply -f -

    oc create secret generic redhat-ymir-agent-keytab \
        --from-file=redhat-ymir-agent.keytab=.secrets/testing-farm/redhat-ymir-agent.keytab \
        --dry-run=client -o yaml | oc apply -f -

    oc create configmap rhel-config \
        --from-file=rhel-config.json=.secrets/testing-farm/rhel-config.json \
        --dry-run=client -o yaml | oc apply -f -
'

echo ""
echo "=========================================="
echo "Environment Ready!"
echo "=========================================="
echo ""
echo "To deploy Ymir:"
echo "  su - crc"
echo "  cd /home/crc/ai-workflows/openshift"
echo "  eval \$(crc oc-env)"
echo "  ./deploy.sh"
echo ""
