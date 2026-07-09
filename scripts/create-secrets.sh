#!/bin/bash
# Create secrets for Ymir deployment from local files or environment variables
#
# Usage:
#   From local machine:
#     1. Set environment variables or prepare files
#     2. SSH to VM and run this script
#
#   Or copy secrets to VM:
#     scp -i <key> -P <port> ~/.secrets/* root@127.0.0.1:/root/secrets/
#     ssh to VM and run this script

set -euo pipefail

SECRETS_DIR="${SECRETS_DIR:-/root/ai-workflows/.secrets/testing-farm}"

echo "=========================================="
echo "Creating Ymir Secrets from Local Files"
echo "=========================================="

# Check if oc is available and logged in
if ! command -v oc &> /dev/null; then
    echo "ERROR: oc command not found. Make sure CRC is running and oc-env is configured."
    echo "Run: eval \$(crc oc-env)"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    echo "ERROR: Not logged in to OpenShift. Please login first:"
    echo "  oc login -u kubeadmin https://api.crc.testing:6443"
    exit 1
fi

# Ensure we're in the right project
PROJECT="${OPENSHIFT_PROJECT:-ymir-test}"
oc project "${PROJECT}" 2>/dev/null || oc new-project "${PROJECT}"

echo "Creating secrets in project: ${PROJECT}"
echo "Secrets directory: ${SECRETS_DIR}"
echo ""

# Create secrets directory if it doesn't exist
mkdir -p "${SECRETS_DIR}"

# Helper function to create secret from env var or file
create_secret() {
    local secret_name="$1"
    local key_name="$2"
    local env_var="$3"
    local file_path="${SECRETS_DIR}/${4:-${key_name}}"

    echo "Creating ${secret_name}..."

    # Try environment variable first
    if [ -n "${!env_var:-}" ]; then
        echo "  Using value from \$${env_var}"
        oc create secret generic "${secret_name}" \
          --from-literal="${key_name}=${!env_var}" \
          --dry-run=client -o yaml | oc apply -f -
        return 0
    fi

    # Try file
    if [ -f "${file_path}" ]; then
        echo "  Using value from ${file_path}"
        oc create secret generic "${secret_name}" \
          --from-literal="${key_name}=$(cat ${file_path})" \
          --dry-run=client -o yaml | oc apply -f -
        return 0
    fi

    # Neither found
    echo "  WARNING: ${secret_name} not found!"
    echo "    Set \$${env_var} or create ${file_path}"
    return 1
}

# Helper for file-based secrets
create_file_secret() {
    local secret_name="$1"
    local secret_key="$2"
    local file_path="${SECRETS_DIR}/${3}"

    echo "Creating ${secret_name}..."

    if [ -f "${file_path}" ]; then
        echo "  Using file from ${file_path}"
        oc create secret generic "${secret_name}" \
          --from-file="${secret_key}=${file_path}" \
          --dry-run=client -o yaml | oc apply -f -
        return 0
    else
        echo "  WARNING: ${secret_name} file not found at ${file_path}"
        return 1
    fi
}

# Track which secrets were created
CREATED=0
MISSING=0

# 1. GitLab Token
if create_secret "gitlab-env" "GITLAB_TOKEN" "GITLAB_TOKEN" "gitlab-token"; then
    ((CREATED++))
else
    ((MISSING++))
fi

# 2. Jira Token
if create_secret "jira-env" "JIRA_TOKEN" "JIRA_TOKEN" "jira-token"; then
    ((CREATED++))
else
    ((MISSING++))
fi

# 3. Testing Farm Token
if create_secret "testing-farm-env" "TESTING_FARM_API_TOKEN" "TESTING_FARM_API_TOKEN" "testing-farm-token"; then
    ((CREATED++))
else
    ((MISSING++))
fi

# 4. Sentry DSN
if create_secret "sentry-env" "SENTRY_DSN" "SENTRY_DSN" "sentry-dsn"; then
    ((CREATED++))
else
    ((MISSING++))
fi

# 5. Vertex AI Key (JSON file)
if create_file_secret "vertex-key" "jotnar-vertex-prod.json" "vertex-key.json"; then
    ((CREATED++))
else
    ((MISSING++))
fi

# 6. Kerberos Keytab
if create_file_secret "redhat-ymir-agent-keytab" "redhat-ymir-agent.keytab" "redhat-ymir-agent.keytab"; then
    ((CREATED++))
else
    ((MISSING++))
fi

# 7. RHEL Config ConfigMap (JSON file)
echo "Creating rhel-config ConfigMap..."
RHEL_CONFIG_FILE="${SECRETS_DIR}/rhel-config.json"
if [ -f "${RHEL_CONFIG_FILE}" ]; then
    echo "  Using file from ${RHEL_CONFIG_FILE}"
    oc create configmap rhel-config \
      --from-file=rhel-config.json="${RHEL_CONFIG_FILE}" \
      --dry-run=client -o yaml | oc apply -f -
    ((CREATED++))
else
    echo "  WARNING: rhel-config.json not found at ${RHEL_CONFIG_FILE}"
    ((MISSING++))
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Secrets created: ${CREATED}"
echo "Secrets missing: ${MISSING}"
echo ""

if [ ${MISSING} -gt 0 ]; then
    echo "⚠️  Some secrets are missing. To provide them:"
    echo ""
    echo "Option 1: Copy from local machine"
    echo "  # From your local machine:"
    echo "  scp -i <ssh_key> -P <port> ~/.secrets/* root@127.0.0.1:/root/secrets/"
    echo "  # Then re-run this script in the VM"
    echo ""
    echo "Option 2: Files in ${SECRETS_DIR}/"
    echo "  ${SECRETS_DIR}/gitlab-token"
    echo "  ${SECRETS_DIR}/jira-token"
    echo "  ${SECRETS_DIR}/testing-farm-token"
    echo "  ${SECRETS_DIR}/sentry-dsn"
    echo "  ${SECRETS_DIR}/vertex-key.json"
    echo "  ${SECRETS_DIR}/redhat-ymir-agent.keytab"
    echo "  ${SECRETS_DIR}/rhel-config.json"
    echo ""
    echo "Option 3: Environment variables (set before running this script)"
    echo "  export GITLAB_TOKEN='your-token'"
    echo "  export JIRA_TOKEN='your-token'"
    echo "  export TESTING_FARM_API_TOKEN='your-token'"
    echo "  export SENTRY_DSN='your-dsn'"
else
    echo "✅ All secrets created successfully!"
    echo ""
    echo "Verify:"
    echo "  oc get secrets"
    echo "  oc get configmap rhel-config"
    echo ""
    echo "Next step: Deploy Ymir"
    echo "  cd /root/ai-workflows/openshift"
    echo "  ./deploy.sh"
fi

echo "=========================================="
