# Testing Farm Quick Start

Deploy and test Ymir on a Testing Farm VM in 3 steps.

## Prerequisites

1. **Get CRC Pull Secret**
   Visit: https://console.redhat.com/openshift/create/local
   Download and save to: `.secrets/testing-farm/pull-secret.txt`

2. **Copy Production Secrets** (or create test ones)
   See: `.secrets/testing-farm/README.md` for instructions

## Quick Start

```bash
# 1. Check secrets are in place
make -f Makefile.testing-farm check-secrets

# 2. Provision VM and deploy Ymir (takes ~15-20 minutes)
make -f Makefile.testing-farm provision-vm

# 3. Wait for deployment to complete, then get SSH details
make -f Makefile.testing-farm ssh-info

# 4. SSH to VM
ssh -i <key-from-above> -p <port-from-above> root@127.0.0.1

# 5. When done, stop VM
make -f Makefile.testing-farm stop-vm
```

## What Happens Automatically

The `provision-vm` target:
1. ✅ Provisions CentOS Stream 9 VM (6 CPU, 12GB RAM, 100GB disk)
2. ✅ Clones ai-workflows repository
3. ✅ Installs OpenShift Local (CRC)
4. ✅ Starts CRC cluster
5. ✅ Creates all OpenShift secrets from `.secrets/testing-farm/`
6. ✅ Deploys all Ymir components (11 Deployments, 2 CronJobs)
7. ✅ Keeps VM running for 30 minutes for manual testing

## Testing Ymir in the VM

Once SSH'd into the VM:

```bash
# Configure oc CLI
eval $(crc oc-env)

# Check pods
oc get pods

# Test issue processing
oc exec deployment/valkey -- valkey-cli LPUSH triage_queue \
  '{"metadata":{"issue":"RHEL-12345"},"attempts":0,"user_triggered":false}'

# Watch agent process it
oc logs -f deployment/triage-agent

# Check queues
oc exec deployment/valkey -- valkey-cli LRANGE triage_queue 0 -1
oc exec deployment/valkey -- valkey-cli LRANGE backport_queue_c9s 0 -1
```

## Full Documentation

- **Complete Guide:** `README-TESTING-FARM-DEPLOYMENT.md`
- **Secrets Setup:** `.secrets/testing-farm/README.md`
- **VM Access:** `README-testing-farm-vm.md`
- **Makefile Help:** `make -f Makefile.testing-farm help`

## Troubleshooting

**Secrets missing?**
```bash
make -f Makefile.testing-farm check-secrets
# Follow instructions in .secrets/testing-farm/README.md
```

**VM not responding?**
```bash
# Check provisioning progress
tail -f /tmp/tmt-ymir.log

# VM takes ~15-20 minutes for full deployment
```

**Need to restart?**
```bash
make -f Makefile.testing-farm stop-vm
make -f Makefile.testing-farm provision-vm
```
