#!/bin/bash
# Provision an Internal Testing Farm VM using tft CLI with nested virtualization
# Requires: pip install --user tft-cli

set -euo pipefail

SECRETS_DIR="$(cd "$(dirname "$0")/../.secrets/testing-farm" && pwd)"

# Check for Internal Testing Farm token
if [ ! -f "$SECRETS_DIR/testing-farm-internal-token" ]; then
    echo "ERROR: Internal Testing Farm token not found at $SECRETS_DIR/testing-farm-internal-token"
    echo "This script uses Internal Testing Farm (Red Hat Ranch) for VPN access"
    exit 1
fi

export TESTING_FARM_API_TOKEN=$(cat "$SECRETS_DIR/testing-farm-internal-token")
export TESTING_FARM_ENDPOINT="https://api.farm.opentlc.redhat.com/v0.1"

# Check if testing-farm is available, install if needed
if ! command -v testing-farm &> /dev/null; then
    echo "Installing Testing Farm CLI..."
    pip install --user tft-cli
    # Add to PATH for this session
    export PATH="$HOME/.local/bin:$PATH"
fi

echo "=========================================="
echo "Provisioning Testing Farm VM"
echo "=========================================="

# Request VM with hardware requirements and environment variables
# Hardware expects key=value pairs like: disk.size='>= 40 GiB'
# Environment vars passed as base64-encoded secrets
# Increased resources for 11 Ymir deployments + infrastructure
testing-farm request \
    --compose CentOS-Stream-10 \
    --arch x86_64 \
    --test-type fmf \
    --hardware 'memory=>= 48 GiB' \
    --hardware 'disk.size=>= 150 GB' \
    --hardware 'cpu.cores=>= 20' \
    --hardware 'virtualization.is-supported=true' \
    --environment "TF_PULL_SECRET=$(base64 -w0 < "$SECRETS_DIR/pull-secret.txt")" \
    --environment "TF_GITLAB_TOKEN=$(base64 -w0 < "$SECRETS_DIR/gitlab-token")" \
    --environment "TF_JIRA_TOKEN=$(base64 -w0 < "$SECRETS_DIR/jira-token")" \
    --environment "TF_TESTING_FARM_TOKEN=$(base64 -w0 < "$SECRETS_DIR/testing-farm-internal-token")" \
    --environment "TF_SENTRY_DSN=$(base64 -w0 < "$SECRETS_DIR/sentry-dsn")" \
    --environment "TF_VERTEX_KEY=$(base64 -w0 < "$SECRETS_DIR/vertex-key.json")" \
    --environment "TF_KEYTAB=$(base64 -w0 < "$SECRETS_DIR/redhat-ymir-agent.keytab")" \
    --environment "TF_RHEL_CONFIG=$(base64 -w0 < "$SECRETS_DIR/rhel-config.json")" \
    --git-url https://github.com/majamassarini/ai-workflows.git \
    --git-ref testing-farm-automation \
    --plan ymir-manual-test/remote

echo ""
echo "=========================================="
echo "Check status with: tft requests list"
echo "Get details with: tft requests get <request-id>"
echo "Cancel with: tft requests cancel <request-id>"
echo "=========================================="
