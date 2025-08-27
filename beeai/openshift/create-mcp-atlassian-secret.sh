#!/bin/bash
# create-mcp-secret.sh

set -e

NAMESPACE="jotnar-prod"
ENV_FILE="../.secrets/mcp-atlassian.env"
SECRET_NAME="mcp-atlassian-secret"

# Check if env file exists
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: $ENV_FILE not found"
    exit 1
fi

# Extract values from env file
JIRA_URL=$(grep -E "^JIRA_URL=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"//;s/"$//')
JIRA_TOKEN=$(grep -E "^JIRA_TOKEN=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"//;s/"$//')

# Check if values were found
if [[ -z "$JIRA_URL" ]]; then
    echo "Error: JIRA_URL not found in $ENV_FILE"
    exit 1
fi

if [[ -z "$JIRA_TOKEN" ]]; then
    echo "Error: JIRA_TOKEN not found in $ENV_FILE"
    exit 1
fi

echo "Creating secret $SECRET_NAME in namespace $NAMESPACE"

# Delete existing secret if it exists
oc delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found

# Create new secret
oc create secret generic "$SECRET_NAME" \
    --from-literal=JIRA_URL="$JIRA_URL" \
    --from-literal=JIRA_PERSONAL_TOKEN="$JIRA_TOKEN" \
    -n "$NAMESPACE"

echo "✅ Secret $SECRET_NAME created successfully"