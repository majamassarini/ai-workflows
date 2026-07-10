#!/bin/bash
# Provision Testing Farm VM and get interactive SSH access
# Requires: pip install --user tft-cli

set -euo pipefail

SECRETS_DIR="$(cd "$(dirname "$0")/../.secrets/testing-farm" && pwd)"

# Check for Internal Testing Farm token
if [ ! -f "$SECRETS_DIR/testing-farm-internal-token" ]; then
    echo "ERROR: Internal Testing Farm token not found at $SECRETS_DIR/testing-farm-internal-token"
    exit 1
fi

export TESTING_FARM_API_TOKEN=$(cat "$SECRETS_DIR/testing-farm-internal-token")
export TESTING_FARM_ENDPOINT="https://api.dev.testing-farm.io/v0.1"

echo "=========================================="
echo "Provisioning Interactive Testing Farm VM"
echo "=========================================="

# Run tmt interactively - it will provision and then give you a shell
cd "$(dirname "$0")/.."
tmt run --verbose \
    -e TF_PULL_SECRET="$(base64 -w0 < "$SECRETS_DIR/pull-secret.txt")" \
    -e TF_GITLAB_TOKEN="$(base64 -w0 < "$SECRETS_DIR/gitlab-token")" \
    -e TF_JIRA_TOKEN="$(base64 -w0 < "$SECRETS_DIR/jira-token")" \
    -e TF_TESTING_FARM_TOKEN="$(base64 -w0 < "$SECRETS_DIR/testing-farm-internal-token")" \
    -e TF_SENTRY_DSN="$(base64 -w0 < "$SECRETS_DIR/sentry-dsn")" \
    -e TF_VERTEX_KEY="$(base64 -w0 < "$SECRETS_DIR/vertex-key.json")" \
    -e TF_KEYTAB="$(base64 -w0 < "$SECRETS_DIR/redhat-ymir-agent.keytab")" \
    -e TF_RHEL_CONFIG="$(base64 -w0 < "$SECRETS_DIR/rhel-config.json")" \
    plan --name ymir-manual-test/remote \
    --interactive login --step provision
