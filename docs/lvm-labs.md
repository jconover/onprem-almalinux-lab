# LVM Labs

## Overview

Logical Volume Manager (LVM) provides a flexible abstraction layer between
physical disks and filesystems. It enables online resizing, snapshots, thin
provisioning, and non-disruptive storage migration -- capabilities that plain
partitions cannot offer. LVM is essential knowledge for production environments
because every enterprise server uses it.

This guide contains five hands-on labs using the db node's extra disks.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  db node (192.168.60.13)                                 │
│                                                          │
│  /dev/vda ─── OS (AlmaLinux root)                        │
│  /dev/vdb ─── 2 GB extra disk (Lab 1-4)                  │
│  /dev/vdc ─── 2 GB extra disk (Lab 1-2, 5)               │
│                                                          │
│  Physical Volumes    Volume Groups    Logical Volumes     │
│  ┌─────────┐        ┌───────────┐    ┌──────────────┐   │
│  │ /dev/vdb │───────▶│           │───▶│ lv_data      │   │
│  └─────────┘        │  vg_data  │    └──────────────┘   │
│  ┌─────────┐        │           │    ┌──────────────┐   │
│  │ /dev/vdc │───────▶│           │───▶│ lv_logs      │   │
│  └─────────┘        └───────────┘    └──────────────┘   │
└──────────────────────────────────────────────────────────┘
```

**Node:** db (192.168.60.13) -- requires Vagrant extra disks provisioned.

## Prerequisites

### Vagrant Extra Disks

The Vagrantfile must attach additional disks to the db node. Verify the disks
exist before starting:

```bash
cd onprem-almalinux-lab/vagrant/alma10
vagrant ssh alma10-db
lsblk
```

Expected output showing vdb and vdc:

```
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
vda    252:0    0   20G  0 disk
├─vda1 252:1    0    1G  0 part /boot
└─vda2 252:2    0   19G  0 part
  ├─almalinux-root 253:0 0   17G  0 lvm  /
  └─almalinux-swap 253:1 0    2G  0 lvm  [SWAP]
vdb    252:16   0    2G  0 disk
vdc    252:32   0    2G  0 disk
```

### Packages

```bash
sudo dnf install -y lvm2 xfsprogs e2fsprogs
```

These are typically installed by default on AlmaLinux.

### No Firewall or SELinux Changes Needed

LVM is a local block-device operation. No firewall ports or SELinux booleans
are required for these labs.

---

## Lab 1: PV/VG/LV Creation and Filesystem Mount

### Step 1 -- Create Physical Volumes

```bash
sudo pvcreate /dev/vdb /dev/vdc
```

Expected output:

```
  Physical volume "/dev/vdb" successfully created.
  Physical volume "/dev/vdc" successfully created.
```

Verify:

```bash
sudo pvs
```

```
  PV         VG   Fmt  Attr PSize PFree
  /dev/vdb        lvm2 ---  2.00g 2.00g
  /dev/vdc        lvm2 ---  2.00g 2.00g
```

### Step 2 -- Create a Volume Group

```bash
sudo vgcreate vg_data /dev/vdb /dev/vdc
```

```
  Volume group "vg_data" successfully created
```

Verify:

```bash
sudo vgs
```

```
  VG      #PV #LV #SN Attr   VSize VFree
  vg_data   2   0   0 wz--n- 3.99g 3.99g
```

### Step 3 -- Create Logical Volumes

```bash
sudo lvcreate -n lv_data -L 1G vg_data
sudo lvcreate -n lv_logs -L 500M vg_data
```

Verify:

```bash
sudo lvs
```

```
  LV      VG      Attr       LSize   Pool Origin Data%  Meta%
  lv_data vg_data -wi-a-----   1.00g
  lv_logs vg_data -wi-a----- 500.00m
```

### Step 4 -- Create Filesystems and Mount

```bash
sudo mkfs.xfs /dev/vg_data/lv_data
sudo mkfs.ext4 /dev/vg_data/lv_logs

sudo mkdir -p /mnt/data /mnt/logs
sudo mount /dev/vg_data/lv_data /mnt/data
sudo mount /dev/vg_data/lv_logs /mnt/logs
```

Verify:

```bash
df -hT /mnt/data /mnt/logs
```

```
Filesystem                   Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_data-lv_data  xfs   1.0G   40M  984M   4% /mnt/data
/dev/mapper/vg_data-lv_logs  ext4  477M  2.3M  445M   1% /mnt/logs
```

### Step 5 -- Add to /etc/fstab for Persistence

```bash
echo '/dev/vg_data/lv_data  /mnt/data  xfs  defaults  0 0' | sudo tee -a /etc/fstab
echo '/dev/vg_data/lv_logs  /mnt/logs  ext4 defaults  0 0' | sudo tee -a /etc/fstab
sudo mount -a   # verify no errors
```

---

## Lab 2: Online Volume Extension

### Extend an XFS Logical Volume (Grow Only)

```bash
sudo lvextend -L +500M /dev/vg_data/lv_data
sudo xfs_growfs /mnt/data
```

XFS uses `xfs_growfs` (operates on the mount point, not the device). XFS
**cannot be shrunk** -- it only supports growing.

Verify:

```bash
df -h /mnt/data
```

### Extend an ext4 Logical Volume (Can Also Shrink)

```bash
sudo lvextend -L +500M /dev/vg_data/lv_logs
sudo resize2fs /dev/vg_data/lv_logs
```

ext4 uses `resize2fs` (operates on the device). ext4 **can be shrunk**, but
the filesystem must be unmounted first and shrinking requires running
`e2fsck` before `resize2fs`.

### One-Command Extend (lvextend -r)

```bash
sudo lvextend -r -L +200M /dev/vg_data/lv_data
```

The `-r` flag automatically calls the appropriate resize tool (xfs_growfs
or resize2fs) after extending the LV.

### Shrink an ext4 Volume (Offline Only)

```bash
sudo umount /mnt/logs
sudo e2fsck -f /dev/vg_data/lv_logs
sudo resize2fs /dev/vg_data/lv_logs 400M
sudo lvreduce -L 400M /dev/vg_data/lv_logs
sudo mount /dev/vg_data/lv_logs /mnt/logs
```

**WARNING:** Always shrink the filesystem FIRST, then shrink the LV. Reversing
this order destroys data.

---

## Lab 3: LVM Snapshots

### Create a Snapshot

Write test data, then snapshot:

```bash
sudo dd if=/dev/urandom of=/mnt/data/testfile bs=1M count=50
sudo lvcreate -s -n snap_data -L 256M /dev/vg_data/lv_data
```

Verify:

```bash
sudo lvs
```

```
  LV        VG      Attr       LSize   Pool Origin  Data%
  lv_data   vg_data owi-aos---   1.70g
  snap_data vg_data swi-a-s--- 256.00m      lv_data 0.00
```

### Corrupt and Restore

```bash
sudo rm -f /mnt/data/testfile
ls /mnt/data/   # testfile is gone

# Restore from snapshot
sudo umount /mnt/data
sudo lvconvert --merge /dev/vg_data/snap_data
sudo mount /dev/vg_data/lv_data /mnt/data
ls /mnt/data/   # testfile is back
```

**Note:** After merge, the snapshot LV is automatically removed.

### Mount a Snapshot Read-Only (Alternative)

```bash
sudo mkdir -p /mnt/snap
sudo mount -o ro,nouuid /dev/vg_data/snap_data /mnt/snap
```

The `nouuid` flag is required for XFS because the snapshot shares the same
UUID as the origin.

---

## Lab 4: Thin Provisioning

Thin provisioning allocates storage on demand rather than up front. You can
over-commit storage -- create LVs whose total size exceeds the physical space.

### Create a Thin Pool

```bash
sudo lvcreate -T -n thinpool -L 1G vg_data
```

### Create Thin Volumes

```bash
sudo lvcreate -T -n thin_vol1 -V 2G vg_data/thinpool
sudo lvcreate -T -n thin_vol2 -V 2G vg_data/thinpool
```

Total virtual size is 4 GB, but only 1 GB of physical space is allocated.

Verify:

```bash
sudo lvs -a
```

### Monitor Thin Pool Usage

```bash
sudo lvs -o +data_percent,metadata_percent vg_data/thinpool
```

**WARNING:** If a thin pool fills to 100%, all thin volumes using it will
be suspended. Monitor thin pool usage with alerts or cron jobs in production.

---

## Lab 5: PV Migration

Move data from one physical disk to another without downtime.

### Migrate vdb to vdc

```bash
sudo pvmove /dev/vdb /dev/vdc
```

This relocates all physical extents from vdb to vdc. Progress is displayed.

Verify:

```bash
sudo pvs
```

vdb should show 0 used extents. Then remove it from the VG:

```bash
sudo vgreduce vg_data /dev/vdb
sudo pvremove /dev/vdb
```

This simulates replacing a failing disk non-disruptively.

---

## Verification / Testing

After completing all labs, run a comprehensive check:

```bash
sudo pvs
sudo vgs
sudo lvs -a -o +devices
lsblk
df -hT | grep -E '(data|logs|thin)'
cat /etc/fstab | grep vg_data
```

Confirm:
- PVs are assigned to the correct VG
- LVs have expected sizes
- Filesystems are mounted and writable
- fstab entries will survive reboot

---

## Troubleshooting

### PV is busy (cannot pvremove)

```bash
# Check what is using it
sudo pvs -o +pv_used
sudo pvdisplay /dev/vdb

# If LVs still reside on it, migrate first
sudo pvmove /dev/vdb
```

### VG has insufficient free space

```bash
sudo vgs -o +vg_free
# Add another PV to the VG
sudo pvcreate /dev/vdd
sudo vgextend vg_data /dev/vdd
```

### LV resize fails: "not enough free space"

```bash
# Check free space in the VG
sudo vgs
# Use percentage instead of absolute size
sudo lvextend -l +100%FREE /dev/vg_data/lv_data
```

### XFS mount fails after snapshot restore

The merge requires the origin to be inactive. Unmount first, merge, then
remount. If the system was rebooted mid-merge, the merge completes
automatically on next LV activation.

### Thin pool full -- volumes suspended

```bash
# Extend the thin pool immediately
sudo lvextend -L +500M vg_data/thinpool
# Resume suspended volumes
sudo lvchange -ay vg_data/thin_vol1
```

---

## Architecture Decision Rationale

### Why LVM over plain partitions?

| Factor | Plain Partitions | LVM |
|--------|-----------------|-----|
| Resize online | No (requires reboot/rescue) | Yes (grow online, ext4 can shrink offline) |
| Span multiple disks | No | Yes (VG aggregates multiple PVs) |
| Snapshots | No | Yes (copy-on-write) |
| Migration | dd + downtime | pvmove, no downtime |
| Thin provisioning | No | Yes |

**Trade-off:** LVM adds a layer of complexity and a small metadata overhead.
For single-disk VMs or containers with ephemeral storage, plain partitions
may be simpler. For any enterprise server managing data, LVM is the standard.

### Thin vs Thick Provisioning

- **Thick (default):** Space allocated immediately. Predictable. No risk of
  surprise "pool full" failures. Use for databases and critical workloads.
- **Thin:** Space allocated on write. Enables overcommit. Use for dev/test,
  home directories, or environments where utilization is low. Requires
  monitoring to avoid pool exhaustion.

### XFS vs ext4

- **XFS:** Default on RHEL/AlmaLinux. Excellent for large files, parallel I/O,
  high throughput. Cannot shrink.
- **ext4:** Mature, well-tested. Supports both grow and shrink. Better for
  smaller filesystems or when shrink capability is required.

---

## Key Concepts to Master

### Understanding Logical Volume Creation

Creating a logical volume from scratch follows a predictable workflow: create PVs
with `pvcreate`, aggregate them into a VG with `vgcreate`, carve out LVs with
`lvcreate`, format with `mkfs`, mount, and add to fstab.

### Understanding Online Filesystem Extension

To extend a filesystem online, use `lvextend -r /dev/vg/lv -L +SIZE`. The `-r`
flag handles both the LV extension and filesystem resize in one command. For XFS,
`xfs_growfs` is called. For ext4, `resize2fs`.

### Understanding XFS Shrink Limitations

XFS only supports growing -- it cannot be shrunk. To reclaim space on XFS, you
must back up, delete the LV, recreate it smaller, and restore. ext4 supports
shrinking but requires the filesystem to be unmounted first.

### Understanding Thick vs Thin Provisioning

Thick provisioning allocates physical storage at creation time. Thin provisioning
allocates on write, allowing overcommit but risking pool exhaustion if not
monitored.

### Non-Disruptive Disk Migration

When a disk is failing, you can move data off without downtime using
`pvmove /dev/failing_disk /dev/new_disk` to relocate extents, then `vgreduce`
and `pvremove` to detach the failing disk.

### Understanding LVM Snapshots

Snapshots use copy-on-write. The snapshot volume only stores blocks that have
changed since the snapshot was created. The origin LV continues to serve live
data. If the snapshot volume fills up, it becomes invalid.

### LVM Status Commands

Use `pvs`/`pvdisplay` for physical volumes, `vgs`/`vgdisplay` for volume groups,
`lvs`/`lvdisplay` for logical volumes. Add `-a` to `lvs` to see internal volumes
(thin pool metadata, etc.).
