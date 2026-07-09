# Complete Guide: Ymir Deployment on Testing Farm VM

Step-by-step guide to deploy and test Ymir on a Testing Farm VM with OpenShift Local (CRC).

## Prerequisites

### On Your Local Machine

1. **Prepare secrets** in `.secrets/testing-farm/` directory:
   ```bash
   cd ~/forges/github/ai-workflows
   ls .secrets/testing-farm/
   ```

   Required files (see `.secrets/testing-farm/README.md` for details):
   - `pull-secret.txt` - Get from https://console.redhat.com/openshift/create/local
   - `gitlab-token`, `jira-token`, `testing-farm-token`, `sentry-dsn`
   - `vertex-key.json`, `redhat-ymir-agent.keytab`, `rhel-config.json`

2. **Quick setup from production** (if you have access):
   ```bash
   # See .secrets/testing-farm/README.md for full commands
   oc login <production-cluster>
   oc project jotnar-ymir--jotnar-ymir
   # Run the oc get secret commands from the README
   ```

---

## Step 1: Provision Testing Farm VM

```bash
cd ~/forges/github/ai-workflows

# Start VM (runs for 30 minutes)
tmt run --all plan --name ymir-interactive/remote --verbose 2>&1 | tee /tmp/tmt-interactive.log &

# Save process ID
echo $! > /tmp/tmt-vm.pid
```

Wait ~60-90 seconds, then find SSH connection details:

```bash
# Get latest run directory
RUN_DIR=$(ls -td /var/tmp/tmt/run-* | head -1)
SSH_KEY="${RUN_DIR}/plans/ymir-interactive/remote/provision/default-0/id_ecdsa"
SSH_PORT=$(grep "port:" /tmp/tmt-interactive.log | tail -1 | awk '{print $2}')

echo "SSH Command:"
echo "ssh -i ${SSH_KEY} -P ${SSH_PORT} root@127.0.0.1"
```

---

## Step 2: SSH into VM

```bash
ssh -i "${SSH_KEY}" -P "${SSH_PORT}" root@127.0.0.1
```

You're now in the VM! Repository is at `/root/ai-workflows`.

---

## Step 3: Verify Secrets Were Copied

The repository clone includes `.secrets/testing-farm/` directory:

```bash
cd /root/ai-workflows
ls -la .secrets/testing-farm/
```

You should see all your secret files. If not, you'll need to create them in the VM or push a commit with the secrets added locally.

---

## Step 4: Install and Setup CRC

```bash
cd /root/ai-workflows

# Install CRC (downloads and installs binary)
./scripts/install-crc.sh

# Setup and start CRC (takes 5-10 minutes)
# This uses .secrets/testing-farm/pull-secret.txt automatically
./scripts/setup-crc.sh
```

Wait for CRC to start. You'll see output like:
```
Started the OpenShift cluster.
The server is accessible via web console at:
  https://console-openshift-console.apps-crc.testing

Log in as administrator:
  Username: kubeadmin
  Password: <password-here>
```

---

## Step 5: Configure OpenShift CLI

```bash
# Configure oc environment
eval $(crc oc-env)

# Get credentials
crc console --credentials

# Login to OpenShift (use password from above)
oc login -u kubeadmin https://api.crc.testing:6443

# Create project for Ymir
oc new-project ymir-test
```

---

## Step 6: Create Ymir Secrets in OpenShift

```bash
# Create secrets from .secrets/testing-farm/ files
./scripts/create-secrets.sh
```

This script automatically:
- Reads files from `.secrets/testing-farm/`
- Creates OpenShift secrets: `gitlab-env`, `jira-env`, `testing-farm-env`, `sentry-env`, `vertex-key`, `redhat-ymir-agent-keytab` # pragma: allowlist secret
- Creates ConfigMap: `rhel-config`

Verify:
```bash
oc get secrets
oc get configmap rhel-config
```

---

## Step 7: Deploy Ymir

```bash
cd /root/ai-workflows/openshift

# Run deployment
./deploy.sh
```

This deploys:
- **Deployments:** triage-agent, backport-agent-c9s/c10s, rebase-agent-c9s/c10s, rebuild-agent-c9s/c10s, mcp-gateway, valkey, phoenix, redis-commander
- **CronJobs:** jira-issue-fetcher, jira-issue-fetcher-todo
- **Services, PVCs, Routes**

---

## Step 8: Wait for Pods to Start

```bash
# Watch pods come up (Ctrl+C to exit)
watch oc get pods

# Or check status
oc get pods
oc get deployments
```

Wait until all pods show `Running` or `Completed`.

---

## Step 9: Test Issue Processing

```bash
# Push a test issue to triage queue
oc exec deployment/valkey -- valkey-cli LPUSH triage_queue \
  '{"metadata":{"issue":"RHEL-12345"},"attempts":0,"user_triggered":false}'

# Watch triage agent process it
oc logs -f deployment/triage-agent

# In another terminal, check queue status
oc exec deployment/valkey -- valkey-cli LRANGE triage_queue 0 -1

# Check if moved to backport queue
oc exec deployment/valkey -- valkey-cli LRANGE backport_queue_c9s 0 -1

# Watch backport agent
oc logs -f deployment/backport-agent-c9s
```

---

## Step 10: Inspect and Debug

### Useful Commands

```bash
# List all resources
oc get all

# Get pod logs
oc logs deployment/triage-agent --tail=50
oc logs deployment/mcp-gateway
oc logs deployment/valkey

# Describe pod for details
oc describe pod <pod-name>

# Check Valkey (Redis) data
oc exec deployment/valkey -- valkey-cli INFO
oc exec deployment/valkey -- valkey-cli KEYS '*'

# View queues
oc exec deployment/valkey -- valkey-cli LRANGE triage_queue 0 -1
oc exec deployment/valkey -- valkey-cli LRANGE backport_queue_c9s 0 -1
oc exec deployment/valkey -- valkey-cli LRANGE error_list 0 -1

# Test MCP Gateway
oc exec deployment/mcp-gateway -- curl http://localhost:8000/health

# Manually trigger CronJob
oc create job test-fetcher-$(date +%s) --from=cronjob/jira-issue-fetcher
oc logs job/test-fetcher-XXXXX -f

# Check events for errors
oc get events --sort-by='.lastTimestamp' | tail -20
```

---

## Step 11: Cleanup

### Inside VM:
```bash
# Stop CRC
crc stop

# Delete CRC instance (optional, saves resources)
crc delete

# Exit VM
exit
```

### On Local Machine:
```bash
# Kill tmt process (cleans up VM)
kill $(cat /tmp/tmt-vm.pid)

# VM auto-cleans up after 30 minutes anyway
```

---

## Troubleshooting

### Missing secrets in VM

If `.secrets/testing-farm/` is empty in the VM:

**Option 1:** Commit and push secrets to your fork (they're git-ignored by default, so you'd need to force add them - **not recommended**)

**Option 2:** Manually copy to VM from your local machine:
```bash
# From local machine
cd ~/forges/github/ai-workflows
tar czf /tmp/secrets.tar.gz .secrets/testing-farm/
scp -i "${SSH_KEY}" -P "${SSH_PORT}" /tmp/secrets.tar.gz root@127.0.0.1:/tmp/

# In VM
cd /root/ai-workflows
tar xzf /tmp/secrets.tar.gz
chmod 600 .secrets/testing-farm/*
```

### CRC won't start

```bash
# Check resources
free -h  # Need 12GB+ RAM
nproc    # Need 6+ CPUs

# Check CRC status
crc status

# Check logs
journalctl -u crc -f
```

### Pods stuck in ImagePullBackOff

```bash
# Force image import
oc import-image beeai-agent --all
oc import-image mcp-server --all
oc import-image valkey --all
```

### Pods CrashLooping

```bash
# Check logs
oc logs <pod-name> --previous

# Common issues:
# 1. Missing secrets: Re-run scripts/create-secrets.sh
# 2. Wrong ConfigMap: Check oc get configmap -o yaml
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| Check VM SSH details | `grep "port:\\|key:" /tmp/tmt-interactive.log` |
| SSH to VM | `ssh -i <key> -P <port> root@127.0.0.1` |
| CRC status | `crc status` |
| CRC credentials | `crc console --credentials` |
| Login to OpenShift | `oc login -u kubeadmin https://api.crc.testing:6443` |
| View pods | `oc get pods` |
| View logs | `oc logs deployment/<name>` |
| Check queues | `oc exec deployment/valkey -- valkey-cli LRANGE <queue> 0 -1` |
| Stop VM | `kill $(cat /tmp/tmt-vm.pid)` |

---

## File Locations

| What | Local Machine | Testing Farm VM |
|------|---------------|-----------------|
| Repository | `~/forges/github/ai-workflows` | `/root/ai-workflows` |
| Secrets | `.secrets/testing-farm/` | `/root/ai-workflows/.secrets/testing-farm/` |
| Scripts | `scripts/` | `/root/ai-workflows/scripts/` |
| OpenShift Manifests | `openshift/` | `/root/ai-workflows/openshift/` |
| SSH Key | `/var/tmp/tmt/run-XXX/.../id_ecdsa` | N/A |
