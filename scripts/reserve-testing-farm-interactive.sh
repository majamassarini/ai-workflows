#!/bin/bash
# Reserve a Testing Farm VM and run the CRC setup from the test plan
# Uses the same preparation steps as the automated test

set -euo pipefail

SECRETS_DIR="$(cd "$(dirname "$0")/../.secrets/testing-farm" && pwd)"

# Check for Internal Testing Farm token
if [ ! -f "$SECRETS_DIR/testing-farm-internal-token" ]; then
    echo "ERROR: Internal Testing Farm token not found at $SECRETS_DIR/testing-farm-internal-token"
    exit 1
fi

export TESTING_FARM_API_TOKEN=$(cat "$SECRETS_DIR/testing-farm-internal-token")
export TESTING_FARM_ENDPOINT="https://api.farm.opentlc.redhat.com/v0.1"

echo "=========================================="
echo "Reserving Testing Farm VM with CRC"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Reserve VM (20 CPUs, 48GB RAM, 150GB disk) for 2 hours"
echo "  2. Run all preparation steps from ymir-manual-test plan"
echo "  3. Leave VM ready for 'su - crc && cd ai-workflows/openshift && ./deploy.sh'"
echo ""
echo "Press Ctrl+C to cancel, or wait 5 seconds..."
sleep 5

# Check for ssh-agent
if ! ssh-add -L &>/dev/null; then
    echo ""
    echo "ERROR: SSH agent not running or no keys loaded"
    echo "Please run:"
    echo "  eval \$(ssh-agent)"
    echo "  ssh-add ~/.ssh/id_rsa"
    exit 1
fi

echo ""
echo "Reserving VM with hardware requirements (20 CPUs, 48GB RAM, 150GB disk)..."
echo "This may take a while if no matching VM is available."
echo "Will timeout after 5 minutes if no VM found."
echo ""

# Reserve VM with timeout
RESERVATION_OUTPUT=$(timeout 300 testing-farm reserve \
    --compose CentOS-Stream-10 \
    --arch x86_64 \
    --hardware 'memory=>= 48 GiB' \
    --hardware 'disk.size=>= 150 GB' \
    --hardware 'cpu.cores=>= 20' \
    --hardware 'virtualization.is-supported=true' \
    --duration 120 2>&1 || echo "TIMEOUT")

if echo "$RESERVATION_OUTPUT" | grep -q "TIMEOUT"; then
    echo ""
    echo "ERROR: Reservation timed out after 5 minutes."
    echo "No VM with requested hardware (20 CPUs, 48GB RAM, 150GB disk) is available."
    echo ""
    echo "You can either:"
    echo "  1. Wait and try again later"
    echo "  2. Request a smaller VM (may not have enough resources for CRC)"
    echo ""
    echo "To reserve without hardware constraints (not recommended for CRC):"
    echo "  testing-farm reserve --compose CentOS-Stream-10 --arch x86_64 --duration 120"
    exit 1
fi

echo "$RESERVATION_OUTPUT"

# Extract SSH info
SSH_INFO=$(echo "$RESERVATION_OUTPUT" | grep -oP 'root@[0-9.]+' | head -1)

if [ -z "$SSH_INFO" ]; then
    echo ""
    echo "ERROR: Could not find SSH connection info"
    echo "Check: testing-farm list --reservations"
    exit 1
fi

echo ""
echo "VM Reserved: $SSH_INFO"
echo "Waiting for SSH..."
sleep 30

# Wait for SSH
MAX_RETRIES=20
for i in $(seq 1 $MAX_RETRIES); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_INFO" "echo ready" &>/dev/null; then
        echo "SSH ready!"
        break
    fi
    echo "Attempt $i/$MAX_RETRIES..."
    sleep 10
    if [ $i -eq $MAX_RETRIES ]; then
        echo "ERROR: SSH timeout"
        exit 1
    fi
done

echo ""
echo "Copying secrets to VM..."
scp -o StrictHostKeyChecking=no -r "$SECRETS_DIR" "$SSH_INFO:/tmp/secrets-upload/"

echo ""
echo "Running CRC setup (this takes ~10-15 minutes)..."
echo ""

# Run all prepare steps from the tmt plan
ssh -o StrictHostKeyChecking=no "$SSH_INFO" bash << 'REMOTE_SETUP'
set -eux

# Install tools
dnf install -y git make ansible-core tar xz

# Clone repo
cd /root
git clone -b testing-farm-automation https://github.com/majamassarini/ai-workflows.git

# Create secrets
mkdir -p /root/ai-workflows/.secrets/testing-farm
mv /tmp/secrets-upload/* /root/ai-workflows/.secrets/testing-farm/

# Extract JSON from YAML if pull secret has frontmatter
if grep -q "^pull_secret:" /root/ai-workflows/.secrets/testing-farm/pull-secret.txt 2>/dev/null; then
    grep "^pull_secret:" /root/ai-workflows/.secrets/testing-farm/pull-secret.txt | cut -d" " -f2- > /tmp/pull-secret-clean.json
    mv /tmp/pull-secret-clean.json /root/ai-workflows/.secrets/testing-farm/pull-secret.txt
fi

# Clone deployment repo
cd /tmp
git clone --depth=1 https://github.com/packit/deployment.git

# Create crc user
cat > /tmp/inventory <<EOI
[all]
localhost ansible_connection=local
EOI
ansible-playbook -i /tmp/inventory /tmp/deployment/playbooks/oc-cluster-user.yml -e user=crc

# Install CRC
cd /root/ai-workflows
./scripts/install-crc.sh

# Copy to crc user
cp -r /root/ai-workflows /home/crc/
chown -R crc:crc /home/crc/ai-workflows

# Add XDG_RUNTIME_DIR to crc user's .bashrc
cat >> /home/crc/.bashrc <<'EOF'
export XDG_RUNTIME_DIR=/run/user/$(id -u)
