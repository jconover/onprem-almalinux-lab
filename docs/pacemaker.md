# Pacemaker/Corosync

## Overview

Pacemaker is a high-availability cluster resource manager that runs on top of
Corosync (the cluster communication layer). Together, they provide automatic
failover of services when a node fails. This lab builds a two-node HA cluster
with the app and app2 nodes, managing a virtual IP address (VIP) and Apache
httpd as cluster resources. When the active node fails, the VIP and httpd
automatically migrate to the surviving node.

**This is an advanced skill that distinguishes senior admins.** Many Linux admins have never set
up Pacemaker. Hands-on HA cluster experience elevates your operational capabilities.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Pacemaker/Corosync HA Cluster                                       │
│                                                                      │
│  ┌─────────────────────┐         ┌─────────────────────┐            │
│  │ app (192.168.60.12)  │◄──────►│ app2 (192.168.60.14) │            │
│  │                      │Corosync│                      │            │
│  │  Pacemaker           │  Ring  │  Pacemaker           │            │
│  │  Corosync            │        │  Corosync            │            │
│  │                      │        │                      │            │
│  │  Resources (active): │        │  Resources (standby):│            │
│  │  - VIP 192.168.60.100│        │  (ready for failover)│            │
│  │  - httpd             │        │                      │            │
│  └─────────────────────┘         └─────────────────────┘            │
│                                                                      │
│  VIP: 192.168.60.100 (floats between nodes)                          │
│  Colocation: VIP and httpd run on the same node                      │
│  Ordering: VIP starts before httpd                                   │
│                                                                      │
│  STONITH: fence_virsh (for KVM/libvirt VMs)                          │
│           or SBD (STONITH Block Device) as alternative               │
└──────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Packages (app and app2 nodes)

```bash
sudo dnf install -y pacemaker corosync pcs fence-agents-all
```

The `pcs` tool is the command-line interface for managing Pacemaker clusters.
`fence-agents-all` provides STONITH agents including `fence_virsh`.

### Additional Packages

```bash
sudo dnf install -y httpd      # the service to be managed
sudo dnf install -y resource-agents  # OCF resource agents
```

### Firewall (app and app2)

```bash
sudo firewall-cmd --permanent --add-service=high-availability
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```

The `high-availability` service opens the Corosync ports (5405/udp) and
pcsd (2224/tcp).

### SELinux

No special booleans needed for basic Pacemaker operation. Pacemaker runs
as root and manages services through their standard systemd units.

### Hostname Resolution

Both nodes must resolve each other's hostnames. Verify:

```bash
# From app:
ping -c 1 app2.lab.local

# From app2:
ping -c 1 app.lab.local
```

---

## Step-by-Step Setup

### Step 1 -- Set hacluster Password (Both Nodes)

The `pcs` package creates a `hacluster` system user. Set the same password
on both nodes:

```bash
# On BOTH app and app2:
echo "HaCluster123" | sudo passwd --stdin hacluster
```

### Step 2 -- Start and Enable pcsd (Both Nodes)

```bash
sudo systemctl enable --now pcsd
```

### Step 3 -- Authenticate Cluster Nodes

From either node (we use app):

```bash
sudo pcs host auth app.lab.local app2.lab.local -u hacluster -p HaCluster123
```

Expected:

```
app.lab.local: Authorized
app2.lab.local: Authorized
```

### Step 4 -- Create the Cluster

```bash
sudo pcs cluster setup lab_cluster app.lab.local app2.lab.local
```

Expected:

```
Sending 'corosync authkey', 'pacemaker authkey' to 'app.lab.local', 'app2.lab.local'
Sending cluster config files to the nodes...
Synchronizing pcsd certificates on nodes...
```

### Step 5 -- Start the Cluster

```bash
sudo pcs cluster start --all
sudo pcs cluster enable --all
```

Verify:

```bash
sudo pcs cluster status
```

Expected:

```
Cluster Status:
 Cluster Summary:
   * Stack: corosync
   * Current DC: app.lab.local (version ...) - partition with quorum
   * 2 nodes configured
   * 0 resource instances configured
 Node List:
   * Online: [ app.lab.local app2.lab.local ]
```

### Step 6 -- Configure STONITH

**WARNING: Never disable STONITH in production.** STONITH (Shoot The Other
Node In The Head) prevents split-brain scenarios where both nodes think they
are the active node and simultaneously modify shared data, causing corruption.

#### Option A: fence_virsh (For KVM/libvirt VMs)

`fence_virsh` connects to the hypervisor via SSH and powers off the VM:

```bash
sudo pcs stonith create fence_app fence_virsh \
    pcmk_host_map="app.lab.local:alma10-app" \
    ip="HYPERVISOR_IP" \
    login="root" \
    identity_file="/root/.ssh/id_rsa" \
    plug="alma10-app" \
    ssh=1 \
    op monitor interval=60s

sudo pcs stonith create fence_app2 fence_virsh \
    pcmk_host_map="app2.lab.local:alma10-app2" \
    ip="HYPERVISOR_IP" \
    login="root" \
    identity_file="/root/.ssh/id_rsa" \
    plug="alma10-app2" \
    ssh=1 \
    op monitor interval=60s
```

#### Option B: SBD (STONITH Block Device)

SBD uses a shared disk (or watchdog timer) for fencing. Suitable for
environments without hypervisor-level fencing:

```bash
# Create shared SBD device (on a shared LUN or virtual disk)
sudo sbd -d /dev/sdb create

# Configure SBD on both nodes
sudo tee /etc/sysconfig/sbd << 'EOF'
SBD_DEVICE="/dev/sdb"
SBD_DELAY_START="no"
SBD_WATCHDOG_DEV="/dev/watchdog"
SBD_WATCHDOG_TIMEOUT="5"
EOF

sudo systemctl enable --now sbd

# Create the STONITH resource
sudo pcs stonith create sbd-fencing fence_sbd \
    devices="/dev/sdb" \
    op monitor interval=60s
```

#### For Lab/Testing Only: Disable STONITH

**Do not do this in production.** For a learning lab where fencing hardware
is unavailable:

```bash
sudo pcs property set stonith-enabled=false
```

In production, disabling STONITH means a network partition or node hang can
cause split-brain. Both nodes may attempt to run the same resource
simultaneously, potentially corrupting shared storage, databases, or
application state. This is the number one mistake new HA administrators make.

### Step 7 -- Set Two-Node Cluster Quorum Policy

A two-node cluster cannot achieve majority quorum when one node fails. Tell
Pacemaker to proceed without quorum:

```bash
sudo pcs property set no-quorum-policy=ignore
```

In a 3+ node cluster, use the default policy (`stop`) to prevent split-brain.

### Step 8 -- Create the VIP Resource

```bash
sudo pcs resource create cluster_vip ocf:heartbeat:IPaddr2 \
    ip=192.168.60.100 \
    cidr_netmask=24 \
    op monitor interval=30s
```

Verify:

```bash
sudo pcs resource status
```

```
  * cluster_vip (ocf:heartbeat:IPaddr2): Started app.lab.local
```

```bash
ip addr show | grep 192.168.60.100
```

### Step 9 -- Prepare httpd for Cluster Management

**Important:** When Pacemaker manages a service, systemd must NOT auto-start
it. Disable the systemd unit:

```bash
# On BOTH nodes:
sudo systemctl disable httpd
sudo systemctl stop httpd
```

Ensure the index pages are distinct so we can verify failover:

```bash
# On app:
echo "HA Cluster - Served by app (192.168.60.12)" | sudo tee /var/www/html/index.html

# On app2:
echo "HA Cluster - Served by app2 (192.168.60.14)" | sudo tee /var/www/html/index.html
```

### Step 10 -- Create the httpd Resource

```bash
sudo pcs resource create cluster_httpd ocf:heartbeat:apache \
    configfile=/etc/httpd/conf/httpd.conf \
    statusurl="http://127.0.0.1/server-status" \
    op monitor interval=30s
```

### Step 11 -- Create Colocation Constraint

The VIP and httpd must run on the same node:

```bash
sudo pcs constraint colocation add cluster_httpd with cluster_vip INFINITY
```

### Step 12 -- Create Ordering Constraint

The VIP must be configured before httpd starts:

```bash
sudo pcs constraint order cluster_vip then cluster_httpd
```

### Step 13 -- Verify Full Configuration

```bash
sudo pcs status
```

Expected output:

```
Cluster name: lab_cluster

WARNINGS:
No stonith devices configured (if STONITH is disabled for lab)

Full List of Resources:
  * cluster_vip  (ocf:heartbeat:IPaddr2): Started app.lab.local
  * cluster_httpd (ocf:heartbeat:apache): Started app.lab.local

Node List:
  * Online: [ app.lab.local app2.lab.local ]
```

```bash
sudo pcs constraint show --full
```

---

## Verification / Testing

### Basic Verification

```bash
# Check cluster status
sudo pcs status

# Verify VIP is active
curl http://192.168.60.100

# Check which node is active
sudo pcs resource show cluster_vip
sudo pcs resource show cluster_httpd

# Verify Corosync ring
sudo corosync-cmapctl | grep member

# Monitor in real-time
sudo crm_mon -1
```

### Failover Test

```bash
# 1. Note which node is active
sudo pcs status | grep "Started"
# Let's say: app.lab.local

# 2. Access the VIP
curl http://192.168.60.100
# Output: HA Cluster - Served by app (192.168.60.12)

# 3. Simulate failure: put the active node in standby
sudo pcs node standby app.lab.local

# 4. Wait for failover (10-30 seconds)
sleep 15

# 5. Check status - resources should move to app2
sudo pcs status

# 6. Access the VIP - should now serve from app2
curl http://192.168.60.100
# Output: HA Cluster - Served by app2 (192.168.60.14)

# 7. Bring the node back
sudo pcs node unstandby app.lab.local

# 8. Resources may or may not move back (depends on resource-stickiness)
sudo pcs status
```

### Alternative Failover Test (Simulate Process Crash)

```bash
# Kill httpd on the active node
ssh app "sudo pkill httpd"

# Pacemaker should detect the failure and restart or migrate
sleep 30
sudo pcs status
curl http://192.168.60.100
```

### Resource Stickiness

By default, resources may migrate back to the original node after it
recovers. To prevent unnecessary failbacks:

```bash
sudo pcs resource defaults update resource-stickiness=100
```

This makes resources "sticky" -- they stay on the current node rather than
moving back, reducing unnecessary service disruptions.

---

## Troubleshooting

### "No resources configured"

```bash
sudo pcs resource status
# Empty output

# Check if resources were created
sudo pcs resource config
```

### Resource in "Stopped" state

```bash
# Check why
sudo pcs resource debug-start cluster_httpd

# Check for failures
sudo pcs resource failcount show cluster_httpd

# Clear failures to allow restart
sudo pcs resource cleanup cluster_httpd
```

### Cluster not forming (nodes not communicating)

```bash
# Check Corosync
sudo corosync-cmapctl | grep member
sudo journalctl -u corosync --no-pager -n 30

# Check pcsd
sudo systemctl status pcsd

# Check firewall
sudo firewall-cmd --list-services | grep high-availability

# Check network connectivity
ping app2.lab.local
```

### Split-brain (both nodes think they are active)

This should not happen with proper STONITH. If it does:

```bash
# Check STONITH status
sudo pcs stonith status

# Check if STONITH is enabled
sudo pcs property show stonith-enabled

# Manually fence a node (CAUTION)
sudo pcs stonith fence app2.lab.local
```

### Resources won't start after cleanup

```bash
# Check resource constraints
sudo pcs constraint show --full

# Check resource configuration
sudo pcs resource config cluster_httpd

# Look for ban locations
sudo pcs constraint location show
# Remove if found
sudo pcs constraint location remove CONSTRAINT_ID
```

### Corosync token timeout

```bash
# Check and adjust
sudo pcs property show
# Default token timeout is 1 second

# Increase for unstable networks (not recommended)
sudo pcs cluster config update totem token=5000
```

---

## Key Commands Reference

| Command | Purpose |
|---------|---------|
| `pcs status` | Overall cluster status |
| `pcs resource status` | Resource status |
| `pcs resource config` | Resource configuration details |
| `pcs constraint show --full` | All constraints |
| `pcs node standby NODE` | Put node in standby (triggers failover) |
| `pcs node unstandby NODE` | Remove standby (node available again) |
| `pcs resource cleanup RESOURCE` | Clear failure counts |
| `pcs resource move RESOURCE NODE` | Manually move resource |
| `pcs resource clear RESOURCE` | Remove manual move constraint |
| `pcs stonith status` | STONITH device status |
| `pcs property set KEY=VALUE` | Set cluster property |
| `crm_mon -1` | One-shot cluster monitor |
| `corosync-cmapctl` | Corosync configuration map |

---

## Architecture Decision Rationale

### Why Pacemaker/Corosync over keepalived?

| Factor | Pacemaker/Corosync | keepalived |
|--------|-------------------|------------|
| Resource management | Full (any service) | VIP only (VRRP) |
| Constraints | Colocation, ordering, location | None |
| Fencing | STONITH (prevents split-brain) | None |
| Complexity | High | Low |
| Use case | Full HA with multiple resources | Simple VIP failover |

**Trade-off:** keepalived is simpler and adequate when you only need a
floating VIP. Pacemaker is necessary when you need to manage multiple
dependent resources with constraints and guaranteed data safety via STONITH.

### Why STONITH is mandatory in production

Without STONITH, a hung node (kernel panic, storage freeze) cannot be
forcibly removed from the cluster. The cluster cannot safely start resources
on another node because the hung node might still be accessing shared
storage. This leads to:
- **Split-brain:** Both nodes running the same service
- **Data corruption:** Both nodes writing to the same filesystem/database
- **Cascading failures:** Resources stuck in unknown state

STONITH guarantees that a failed node is truly dead (powered off or reset)
before resources are started elsewhere.

### Why disable systemd for cluster-managed services?

If systemd starts httpd automatically, it conflicts with Pacemaker's
resource management. Pacemaker needs full control over service start/stop
to enforce constraints (ordering, colocation) and to correctly detect
failures. Having both systemd and Pacemaker managing the same service leads
to unpredictable behavior.

### Two-node cluster limitations

Two-node clusters cannot achieve quorum when one node fails (1 out of 2 is
not a majority). The `no-quorum-policy=ignore` setting is required. In
production, consider:
- **Three-node clusters:** True majority quorum possible
- **Quorum device (qdevice):** A lightweight third-party arbitrator that
  provides the deciding vote: `pcs quorum device add model net host=QNET_IP`

---

## Key Concepts to Master

### STONITH and Why It Matters

STONITH (Shoot The Other Node In The Head) is the fencing mechanism that
ensures a failed node is truly dead before resources are migrated. Without
it, a hung node might still be writing to shared storage while the cluster
starts the same service on another node, causing data corruption. Never
disable STONITH in production.

### The Difference Between Pacemaker and Corosync

Corosync handles cluster communication -- node membership, messaging,
and quorum. Pacemaker is the resource manager that runs on top of Corosync
and makes decisions about where to run resources, handles failover, and
enforces constraints. They are complementary: Corosync is the network layer,
Pacemaker is the brain.

### Understanding Colocation Constraints

A colocation constraint ensures two resources run on the same node. For
example, a VIP and an application must be colocated so that traffic reaching
the VIP is served by the correct node. Without colocation, the VIP could be
on one node while the application runs on another.

### Testing HA Cluster Failover

Put the active node in standby with `pcs node standby NODENAME`. Verify
that resources migrate to the other node with `pcs status`. Test that the
service is accessible via the VIP. Then unstandby the node and verify it
rejoins. You can also simulate a process crash with `pkill` or a node
crash by stopping Corosync.

### Quorum and Why It Matters

Quorum is the minimum number of cluster nodes that must be online to make
decisions (majority: N/2 + 1). It prevents split-brain in network partitions.
If a partition occurs, only the partition with quorum can run resources.
Two-node clusters require special handling (no-quorum-policy=ignore or a
quorum device).

### Adding a Third Node to the Cluster

Run `pcs host auth NEWNODE`, then `pcs cluster node add NEWNODE`. Update
the no-quorum-policy to the default (`stop`) since three nodes can achieve
true quorum. Update STONITH configuration to include the new node.
