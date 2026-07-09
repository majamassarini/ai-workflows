#!/bin/bash
# Install OpenShift Local (CRC) for Ymir testing
# This script downloads and installs CRC on CentOS Stream 9

set -euo pipefail

CRC_VERSION="${CRC_VERSION:-2.62.0}"
CRC_ARCH="amd64"
CRC_PLATFORM="linux"
CRC_DOWNLOAD_URL="https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/crc/${CRC_VERSION}/crc-${CRC_PLATFORM}-${CRC_ARCH}.tar.xz"

echo "=========================================="
echo "Installing OpenShift Local (CRC) ${CRC_VERSION}"
echo "=========================================="

# Check if already installed
if command -v crc &> /dev/null; then
    echo "CRC is already installed:"
    crc version
    exit 0
fi

# Install dependencies
echo "Installing dependencies..."
dnf install -y \
    libvirt \
    libvirt-daemon-kvm \
    NetworkManager \
    qemu-kvm \
    tar \
    xz

# Download CRC
echo "Downloading CRC ${CRC_VERSION}..."
cd /tmp
curl -L -o crc.tar.xz "${CRC_DOWNLOAD_URL}"

# Extract
echo "Extracting CRC..."
tar -xf crc.tar.xz

# Install binary
echo "Installing CRC binary..."
# Disable pipefail temporarily to avoid SIGPIPE from head
set +o pipefail
CRC_DIR=$(tar -tf crc.tar.xz | head -1 | cut -f1 -d"/")
set -o pipefail
cp "${CRC_DIR}/crc" /usr/local/bin/
chmod +x /usr/local/bin/crc

# Cleanup
rm -rf crc.tar.xz "${CRC_DIR}"

# Verify installation
echo ""
echo "CRC installed successfully:"
crc version

echo ""
echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo "1. Setup CRC:"
echo "   crc setup"
echo ""
echo "2. Start CRC with pull secret:"
echo "   crc start --pull-secret-file /path/to/pull-secret.txt"
echo ""
echo "   Get pull secret from:"
echo "   https://console.redhat.com/openshift/create/local"
echo ""
echo "3. Configure oc CLI:"
echo "   eval \$(crc oc-env)"
echo "   oc login -u kubeadmin https://api.crc.testing:6443"
echo "=========================================="
