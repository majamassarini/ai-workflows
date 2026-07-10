#!/bin/bash
# Complete CRC and Ymir setup script for an existing VM
# Based on ymir-manual-test.fmf plan
#
# Usage: Run this on the VM after you've reserved it
#   ssh root@<VM-IP>
#   ./setup-existing-vm.sh

set -euo pipefail

echo "=========================================="
echo "Complete CRC Setup for Ymir"
echo "=========================================="
echo ""

# Check VM resources
TOTAL_CPUS=$(nproc)
TOTAL_MEM=$(free -m | awk '/^Mem:/ {print $2}')

echo "VM Resources:"
echo "  CPUs: $TOTAL_CPUS"
echo "  Memory: ${TOTAL_MEM} MiB ($((TOTAL_MEM / 1024)) GB)"
echo ""

# Calculate CRC resources (same as test plan with adjustments)
CRC_CPUS=$((TOTAL_CPUS - 2))
CRC_MEMORY=$((TOTAL_MEM - 4096))
CRC_DISK=130

# Ensure minimums
[ $CRC_CPUS -lt 4 ] && CRC_CPUS=4
[ $CRC_MEMORY -lt 16384 ] && CRC_MEMORY=16384

echo "CRC will use:"
echo "  CPUs: $CRC_CPUS"
echo "  Memory: $CRC_MEMORY MiB ($((CRC_MEMORY / 1024)) GB)"
echo "  Disk: $CRC_DISK GB"
echo ""

# Install tools
echo "Installing tools..."
dnf install -y git make ansible-core tar xz

# Clone repo
echo "Cloning ai-workflows repo..."
cd /root
if [ ! -d "ai-workflows" ]; then
    git clone -b testing-farm-automation https://github.com/majamassarini/ai-workflows.git
fi

# Clone deployment repo
echo "Cloning deployment repo..."
cd /tmp
if [ ! -d "deployment" ]; then
    git clone --depth=1 https://github.com/packit/deployment.git
fi

# Create crc user
echo "Creating crc user..."
cat > /tmp/inventory <<EOI
[all]
localhost ansible_connection=local
EOI
ansible-playbook -i /tmp/inventory /tmp/deployment/playbooks/oc-cluster-user.yml -e user=crc

# Install CRC
echo "Installing CRC..."
cd /root/ai-workflows
./scripts/install-crc.sh

# Copy to crc user
echo "Copying files to crc user..."
cp -r /root/ai-workflows /home/crc/
chown -R crc:crc /home/crc/ai-workflows

# Add XDG_RUNTIME_DIR to crc user's .bashrc
echo "Configuring crc user environment..."
cat >> /home/crc/.bashrc <<'EOFBASHRC'
export XDG_RUNTIME_DIR=/run/user/$(id -u)
EOFBASHRC

# Configure and setup CRC
echo "Configuring CRC..."
su - crc -c "
    set -eux
    crc config set consent-telemetry no
    crc config set disable-update-check true
    crc config set enable-cluster-monitoring false
    crc config set cpus ${CRC_CPUS}
    crc config set memory ${CRC_MEMORY}
    crc config set disk-size ${CRC_DISK}
    crc setup
"

echo ""
echo "=========================================="
echo "CRC Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Copy secrets from your local machine:"
echo "   scp -r /home/mmassari/forges/github/ai-workflows/.secrets/testing-farm root@3.128.184.105:/root/ai-workflows/.secrets/"
echo ""
echo "2. Then start CRC and deploy Ymir:"
echo "   ./start-and-deploy.sh"
echo ""
