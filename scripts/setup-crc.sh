#!/bin/bash
# Setup and start OpenShift Local (CRC) for Ymir testing

set -euo pipefail

PULL_SECRET_FILE="${CRC_PULL_SECRET_FILE:-/root/ai-workflows/.secrets/testing-farm/pull-secret.txt}"

echo "=========================================="
echo "Setting up OpenShift Local (CRC)"
echo "=========================================="

# Check if CRC is installed
if ! command -v crc &> /dev/null; then
    echo "ERROR: CRC is not installed. Run install-crc.sh first."
    exit 1
fi

# Check for pull secret
if [ ! -f "${PULL_SECRET_FILE}" ]; then
    echo "ERROR: Pull secret not found at ${PULL_SECRET_FILE}"
    echo ""
    echo "Please create the pull secret file:"
    echo "1. Get pull secret from: https://console.redhat.com/openshift/create/local"
    echo "2. Save it to: ${PULL_SECRET_FILE}"
    echo ""
    echo "Or set CRC_PULL_SECRET_FILE environment variable to the correct path"
    exit 1
fi

# Stop any running CRC instance
echo "Stopping any existing CRC instance..."
crc stop || true
crc delete -f || true

# Run CRC setup
echo "Running CRC setup..."
crc setup

# Configure CRC for testing environment
echo "Configuring CRC..."
crc config set cpus 6
crc config set memory 12288  # 12GB
crc config set disk-size 60  # 60GB (doesn't need full 100GB)
crc config set consent-telemetry no

# Start CRC
echo "Starting CRC (this will take 5-10 minutes)..."
crc start --pull-secret-file "${PULL_SECRET_FILE}"

# Get credentials
echo ""
echo "=========================================="
echo "CRC Started Successfully!"
echo "=========================================="
crc console --credentials

echo ""
echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo "1. Configure oc CLI:"
echo "   eval \$(crc oc-env)"
echo ""
echo "2. Login as kubeadmin:"
echo "   crc console --credentials  # Get password"
echo "   oc login -u kubeadmin https://api.crc.testing:6443"
echo ""
echo "3. Create project for Ymir:"
echo "   oc new-project ymir-test"
echo ""
echo "4. Deploy Ymir:"
echo "   cd /root/ai-workflows/openshift"
echo "   # First create secrets (see generate-test-secrets.sh)"
echo "   ./deploy.sh"
echo "=========================================="
