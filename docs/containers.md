# Containers on AlmaLinux

## 1. Overview

Container technology is a core competency for Senior Linux Admin roles. RHEL 8+
(and AlmaLinux as its downstream) replaced Docker with a suite of daemonless,
rootless, OCI-compliant tools: **Podman**, **Buildah**, and **Skopeo**. Understanding
why Red Hat made this shift and how to operate these tools is frequently tested
in interviews.

This document covers:
- Podman as a Docker-compatible container runtime
- Rootless containers and user namespaces
- Pods (multi-container groups sharing a network namespace)
- Quadlet (systemd integration for containers)
- Buildah and Skopeo for image building and management
- Kubernetes awareness (CRI-O, kubectl basics)
- SELinux and container security

---

## 2. Architecture

### Lab Node Involvement

```
alma10-app / alma10-app2   -- Run containerized web services
alma10-admin               -- Container image builds, registry mirror
alma10-bastion             -- Podman pod for HAProxy + monitoring sidecar
```

### Tool Ecosystem

```
+------------------+     +------------------+     +------------------+
|     Podman       |     |     Buildah      |     |     Skopeo       |
|  Run containers  |     |  Build images    |     |  Copy/inspect    |
|  Manage pods     |     |  No daemon       |     |  images between  |
|  Docker-compat   |     |  Scratch builds  |     |  registries      |
+------------------+     +------------------+     +------------------+
         |                        |                        |
         +------------------------+------------------------+
                                  |
                        OCI Image Format
                    (compatible with Docker)
```

### Podman vs Docker

| Feature              | Podman                           | Docker                          |
|----------------------|----------------------------------|---------------------------------|
| **Daemon**           | Daemonless (fork/exec)           | Central daemon (dockerd)        |
| **Root required**    | No (rootless by default)         | Yes (or docker group)           |
| **Process model**    | Each container is a child process| All containers are children of daemon |
| **Systemd integration** | Native via Quadlet            | Requires wrapper scripts        |
| **Pod concept**      | Built-in (Kubernetes-style)      | Not native (use compose)        |
| **CLI compatibility**| `alias docker=podman` works      | N/A                             |
| **Socket**           | Per-user socket (optional)       | /var/run/docker.sock (root)     |
| **Image format**     | OCI                              | OCI (also Docker v2)            |
| **Compose**          | podman-compose (or compose v2)   | docker-compose / compose v2     |
| **Security**         | SELinux container_t, rootless     | Requires SELinux + root         |

**Why RHEL chose Podman**: The Docker daemon is a single point of failure and
runs as root, creating a security risk. If the daemon crashes, all containers
die. Podman's fork/exec model means each container is an independent process,
managed by the user's login session or systemd. No root daemon means reduced
attack surface.

---

## 3. Prerequisites

```bash
# Install container tools on AlmaLinux 9/10
sudo dnf install -y podman buildah skopeo

# Verify installation
podman --version
buildah --version
skopeo --version

# Install podman-compose (optional, for docker-compose compatibility)
sudo dnf install -y podman-compose
```

### Rootless Prerequisites

```bash
# Verify subuid/subgid mappings exist for your user
grep $USER /etc/subuid
grep $USER /etc/subgid
# Output: justin:100000:65536

# If missing, add them:
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER

# Reset user namespace (required after modifying subuid/subgid)
podman system migrate
```

---

## 4. Step-by-Step Setup / Deep Dive

### 4.1 Podman Basic Commands

Every Docker command has a Podman equivalent:

```bash
# Pull an image
podman pull docker.io/library/httpd:2.4

# List images
podman images

# Run a container (detached, with port mapping)
podman run -d --name myweb -p 8080:80 httpd:2.4

# List running containers
podman ps

# List all containers (including stopped)
podman ps -a

# View logs
podman logs myweb
podman logs -f myweb        # Follow mode

# Execute command inside container
podman exec -it myweb /bin/bash

# Inspect container details (JSON)
podman inspect myweb

# Stop and remove
podman stop myweb
podman rm myweb

# Remove image
podman rmi httpd:2.4

# Clean up everything
podman system prune -af
```

### 4.2 Building Container Images

#### Containerfile (Dockerfile equivalent)

```dockerfile
# Containerfile for a custom Apache setup
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf install -y httpd mod_ssl && \
    microdnf clean all

COPY index.html /var/www/html/
COPY vhost.conf /etc/httpd/conf.d/

EXPOSE 80 443

CMD ["/usr/sbin/httpd", "-D", "FOREGROUND"]
```

```bash
# Build the image
podman build -t lab-web:1.0 -f Containerfile .

# Run it
podman run -d --name lab-web -p 8080:80 lab-web:1.0

# Verify
curl http://localhost:8080/
```

### 4.3 Rootless Containers Deep Dive

Rootless containers run entirely in user space without any root privileges.

**How they work**:

1. **User namespaces**: The kernel maps UID 0 inside the container to a
   high-numbered UID outside (e.g., 100000). The container "thinks" it is
   root, but the host sees an unprivileged user.

2. **`/etc/subuid` and `/etc/subgid`**: Define the range of subordinate UIDs
   available to each user. For example, `justin:100000:65536` means user
   `justin` can map container UIDs 0-65535 to host UIDs 100000-165535.

3. **Networking**: Rootless containers use `slirp4netns` or `pasta` for
   network connectivity without requiring root for bridge setup.

4. **Storage**: Images are stored in `~/.local/share/containers/` instead of
   `/var/lib/containers/`.

```bash
# Verify rootless operation
podman run --rm alpine id
# Output: uid=0(root) gid=0(root) -- but this is UID 0 INSIDE the namespace

# See the actual host UID
podman top $(podman ps -q) user huser
# HUSER shows the real host UID (e.g., 100000)

# Check unshare mapping
podman unshare cat /proc/self/uid_map
#          0       1000          1     (container root = host UID 1000)
#          1     100000      65536     (container 1-65535 = host 100000-165535)
```

**Rootless limitations**:
- Cannot bind to ports below 1024 (unless `net.ipv4.ip_unprivileged_port_start=0`)
- No `--privileged` (use `--cap-add` for specific capabilities)
- Some volume mount permissions require `:Z` or `:z` SELinux labels

### 4.4 Pods

A **pod** is a group of containers sharing a network namespace (like a Kubernetes pod).

```bash
# Create a pod with port mappings (ports go on the pod, not individual containers)
podman pod create --name web-pod -p 8080:80 -p 9100:9100

# Run httpd inside the pod
podman run -d --pod web-pod --name web httpd:2.4

# Run node_exporter as a sidecar in the same pod
podman run -d --pod web-pod --name exporter \
  quay.io/prometheus/node-exporter:latest

# Both containers share localhost -- web is on :80, exporter on :9100
# From outside, access via pod's port mappings: :8080 and :9100

# List pods
podman pod list

# Inspect pod
podman pod inspect web-pod

# Stop/start the entire pod
podman pod stop web-pod
podman pod start web-pod

# Remove pod and all its containers
podman pod rm -f web-pod
```

### 4.5 Quadlet: systemd Integration for Containers

Quadlet is the modern way to run containers as systemd services. Instead of
writing custom unit files, you create `.container` files that systemd-generators
convert into proper unit files at boot.

#### Rootless Quadlet Location

```
~/.config/containers/systemd/    # Per-user (rootless)
/etc/containers/systemd/         # System-wide (rootful)
```

#### Example: httpd as a Quadlet Container

Create `~/.config/containers/systemd/lab-web.container`:

```ini
[Unit]
Description=Lab Web Server Container
After=network-online.target

[Container]
Image=docker.io/library/httpd:2.4
PublishPort=8080:80
Volume=/srv/www:/usr/local/apache2/htdocs:Z,ro
AutoUpdate=registry

# Environment variables
Environment=APACHE_LOG_DIR=/var/log/apache2

# Health check
HealthCmd=curl -f http://localhost/ || exit 1
HealthInterval=30s

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

```bash
# Reload systemd to pick up new Quadlet files
systemctl --user daemon-reload

# Start the container service
systemctl --user start lab-web

# Enable at login
systemctl --user enable lab-web

# Check status
systemctl --user status lab-web

# View logs through journald
journalctl --user -u lab-web -f

# Enable lingering so user services start at boot (not just at login)
loginctl enable-linger $USER
```

#### Quadlet for Pods

Create `~/.config/containers/systemd/web.pod`:

```ini
[Pod]
PodName=web-pod
PublishPort=8080:80
PublishPort=9100:9100
```

Then reference the pod in `.container` files:

```ini
[Container]
Image=httpd:2.4
Pod=web.pod
```

### 4.6 Buildah: Building OCI Images

Buildah builds OCI images without a running daemon. It supports both
Dockerfile/Containerfile and a scriptable shell interface.

```bash
# Build from Containerfile (same as podman build)
buildah bud -t lab-web:1.0 .

# Scriptable build (no Containerfile needed)
container=$(buildah from registry.access.redhat.com/ubi9/ubi-minimal)
buildah run $container -- microdnf install -y httpd
buildah copy $container index.html /var/www/html/
buildah config --port 80 $container
buildah config --cmd '/usr/sbin/httpd -D FOREGROUND' $container
buildah commit $container lab-web:2.0

# List local images
buildah images

# Push to registry
buildah push lab-web:2.0 docker://registry.example.com/lab-web:2.0
```

**Buildah advantages over `podman build`**:
- Can build from scratch (empty) images
- Fine-grained layer control
- No running container needed during build
- Useful in CI/CD where Docker daemon is not available

### 4.7 Skopeo: Image Inspection and Transfer

Skopeo inspects and copies images between registries without pulling them locally.

```bash
# Inspect a remote image (no pull required)
skopeo inspect docker://docker.io/library/httpd:2.4

# Copy image between registries
skopeo copy docker://docker.io/library/httpd:2.4 \
             docker://registry.lab.local:5000/httpd:2.4

# Copy to a local directory (OCI layout)
skopeo copy docker://docker.io/library/httpd:2.4 \
             oci:/tmp/httpd-oci:2.4

# Copy to a Docker archive (tar)
skopeo copy docker://docker.io/library/httpd:2.4 \
             docker-archive:/tmp/httpd.tar:httpd:2.4

# Sync an entire repository
skopeo sync --src docker --dest dir docker.io/library/httpd /tmp/httpd-mirror/

# List tags for a remote image
skopeo list-tags docker://docker.io/library/httpd
```

### 4.8 Kubernetes Awareness

#### Podman and Kubernetes Interop

```bash
# Generate Kubernetes YAML from a running pod
podman generate kube web-pod > web-pod.yaml

# Deploy Kubernetes YAML with Podman (no K8s cluster needed)
podman play kube web-pod.yaml

# Tear down
podman play kube --down web-pod.yaml
```

#### kubectl Basics

```bash
# Core objects
kubectl get pods                     # List pods
kubectl get deployments              # List deployments
kubectl get services                 # List services
kubectl get nodes                    # List cluster nodes

# Create from YAML
kubectl apply -f deployment.yaml

# Describe a resource (detailed info + events)
kubectl describe pod mypod

# View logs
kubectl logs mypod
kubectl logs -f mypod               # Follow

# Execute command in pod
kubectl exec -it mypod -- /bin/bash

# Scale a deployment
kubectl scale deployment myapp --replicas=3

# Port forward for local testing
kubectl port-forward svc/myapp 8080:80
```

#### CRI-O: RHEL's Preferred Container Runtime for Kubernetes

CRI-O is a lightweight container runtime implementing the Kubernetes Container
Runtime Interface (CRI). It is RHEL's recommended runtime for OpenShift and
Kubernetes.

```
Kubernetes kubelet
      |
  CRI (gRPC API)
      |
    CRI-O           (or containerd -- the other major CRI implementation)
      |
   runc / crun      (OCI runtime that creates Linux namespaces/cgroups)
      |
  Linux kernel
```

**Why CRI-O over containerd for RHEL shops**:
- Developed alongside Kubernetes, only implements what K8s needs
- Integrates with SELinux and RHEL security features
- Used by OpenShift (Red Hat's Kubernetes distribution)
- Smaller scope = smaller attack surface

### 4.9 SELinux and Containers

SELinux confines containers using the `container_t` type.

```bash
# Check SELinux context of a running container process
ps -eZ | grep httpd
# system_u:system_r:container_t:s0:c123,c456  ... httpd

# Volume mounts need SELinux labels
podman run -v /srv/data:/data:Z httpd   # :Z = private label (relabel)
podman run -v /srv/data:/data:z httpd   # :z = shared label (multiple containers)

# Check file contexts
ls -lZ /srv/data/
# Should show container_file_t after :Z mount

# If SELinux blocks container operations
ausearch -m avc -ts recent
sealert -a /var/log/audit/audit.log
```

**Common SELinux booleans for containers**:

```bash
# Allow containers to manage the network stack
setsebool -P container_manage_cgroup on

# Allow containers to connect to any port
setsebool -P container_connect_any on

# List all container-related booleans
getsebool -a | grep container
```

---

## 5. Verification / Testing

### Basic Container Operations

```bash
# Verify Podman rootless works
podman run --rm docker.io/library/alpine echo "Rootless works"

# Verify networking
podman run -d --name test -p 8888:80 httpd:2.4
curl -s http://localhost:8888/ | head -5
podman rm -f test

# Verify pod networking
podman pod create --name test-pod -p 8888:80
podman run -d --pod test-pod httpd:2.4
curl -s http://localhost:8888/ | head -5
podman pod rm -f test-pod
```

### Quadlet Verification

```bash
# Check systemd generator output
/usr/lib/systemd/system-generators/podman-system-generator --user --dryrun

# Verify service is running
systemctl --user is-active lab-web

# Check container health
podman healthcheck run lab-web
```

### Image Verification

```bash
# Verify image layers
podman history lab-web:1.0

# Verify image labels and config
podman inspect lab-web:1.0 | jq '.[0].Config'

# Scan for vulnerabilities (if available)
podman image scan lab-web:1.0
```

---

## 6. Troubleshooting

| Issue | Diagnostic | Fix |
|-------|-----------|-----|
| `ERRO[0000] cannot find UID/GID mappings` | Missing subuid/subgid | `sudo usermod --add-subuids 100000-165535 $USER` |
| `Permission denied` on volume mount | SELinux blocking | Add `:Z` or `:z` suffix to volume mount |
| Container cannot bind port 80 | Unprivileged port restriction | Use port > 1024, or `sysctl net.ipv4.ip_unprivileged_port_start=80` |
| `Error: OCI runtime error` | crun/runc issue | Check `podman info` for runtime, update with `dnf update` |
| Quadlet service fails to start | Generator not finding file | Verify file is in correct directory, run `systemctl --user daemon-reload` |
| Image pull fails with TLS error | Registry certificate issue | Add cert to `/etc/pki/ca-trust/source/anchors/` and `update-ca-trust` |
| Rootless container DNS not working | `slirp4netns` issue | Try `podman run --network=pasta` or check `/etc/resolv.conf` inside container |
| `WARN[0000] "/" is not a shared mount` | Mount propagation | `sudo mount --make-rshared /` |

### Container Debugging

```bash
# Inspect failed container
podman logs <container-id>
podman inspect <container-id> | jq '.[0].State'

# Check resource usage
podman stats

# View container processes
podman top <container-id>

# Export filesystem for analysis
podman export <container-id> -o container-fs.tar
```

---

## 7. Architecture Decision Rationale

### Why Podman over Docker on AlmaLinux

**Decision**: Use Podman as the primary container runtime.

**Rationale**:
- Podman is the default container tool in RHEL 9/10 and AlmaLinux
- Daemonless architecture eliminates single point of failure
- Rootless by default aligns with security best practices
- Fork/exec model integrates naturally with systemd
- OCI-compatible, so all Docker images work unchanged
- Docker is not available in RHEL repos (requires external repo)

### Why Quadlet over podman generate systemd

**Decision**: Use Quadlet `.container` files instead of generated unit files.

**Rationale**:
- `podman generate systemd` was deprecated in Podman 4.4+
- Quadlet files are declarative and easier to read/maintain
- Quadlet integrates with systemd generators for proper boot ordering
- Supports auto-update via `AutoUpdate=registry`
- Pod support via `.pod` files
- Quadlet is the documented standard going forward

### Why Pods for Multi-Container Applications

**Decision**: Use Podman pods for co-located containers.

**Rationale**:
- Pods group containers that must share network namespace (like K8s)
- A web server + monitoring sidecar share localhost
- `podman generate kube` produces valid Kubernetes YAML from pods
- Easier migration path to Kubernetes later
- Alternative (docker-compose) requires an additional tool and does not map to K8s

---

## 8. Interview Talking Points

### "Why did RHEL move to Podman?"

> "Red Hat moved to Podman to eliminate the Docker daemon, which was a single
> point of failure running as root. If the Docker daemon crashes, all containers
> die. Podman uses a fork/exec model where each container is an independent
> process. It runs rootless by default, reducing the attack surface. It also
> integrates natively with systemd -- containers can be managed as systemd
> services via Quadlet. The CLI is Docker-compatible, so `alias docker=podman`
> works for most workflows."

### "How do rootless containers work?"

> "Rootless containers use Linux user namespaces to map UID 0 inside the container
> to an unprivileged UID on the host. The mapping is defined in `/etc/subuid`
> and `/etc/subgid` -- for example, my user gets UIDs 100000 through 165535.
> Inside the container, processes run as root, but the host sees them as my
> user's subordinate UIDs. Networking uses `slirp4netns` or `pasta` instead of
> bridge networking, since creating bridges requires root. Storage lives in
> `~/.local/share/containers/` in the user's home directory."

### "What is Quadlet and when would you use it?"

> "Quadlet is systemd integration for Podman containers. You write a `.container`
> file in `/etc/containers/systemd/` (or the user equivalent) that declares the
> image, ports, volumes, and restart policy. At boot, a systemd generator converts
> this into a proper systemd unit. I use Quadlet for any container that should
> run as a persistent service -- web servers, monitoring agents, databases.
> It supports health checks, auto-updates from registries, and pod grouping.
> It replaced `podman generate systemd` which was deprecated in Podman 4.4."

### "Explain the container runtime landscape."

> "At the bottom is the OCI runtime -- `runc` or `crun` -- which creates Linux
> namespaces and cgroups. Above that, you have high-level runtimes that manage
> image pulls, storage, and lifecycle. The three main ones are: Docker (daemon-based,
> the original), containerd (extracted from Docker, used by most cloud K8s),
> and CRI-O (purpose-built for Kubernetes, used by OpenShift). Podman is a
> client tool, not a daemon -- it uses the same OCI runtimes but operates
> in a daemonless, rootless model. For Kubernetes, CRI-O and containerd both
> implement the CRI interface that kubelet uses."

### "How do you handle container security?"

> "Multiple layers. First, rootless containers so nothing runs as host root.
> Second, SELinux with `container_t` type confines what containers can access.
> Third, `:Z` volume labels ensure files get the right SELinux context. Fourth,
> minimal base images like UBI-minimal to reduce attack surface. Fifth, image
> scanning in CI for known vulnerabilities. Sixth, read-only root filesystem
> where possible (`--read-only`). Seventh, drop all capabilities and add back
> only what is needed (`--cap-drop=ALL --cap-add=NET_BIND_SERVICE`)."

### "How would you containerize a legacy application?"

> "Start by understanding the application's dependencies -- libraries, config
> files, port bindings, filesystem paths. Create a Containerfile using a
> UBI base image, install dependencies, copy the application. Test locally
> with `podman run`. Create a Quadlet file for systemd management. For
> persistent data, use named volumes or bind mounts with `:Z` labels.
> For multiple processes, use a pod with one container per process. Test
> with `podman play kube` to validate the Kubernetes migration path."
