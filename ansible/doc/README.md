# Ansible layer

The Ansible layer of **PostgreSQL-Open-Automation-Framework** takes the VM fleet
provisioned by Terraform and installs a production-style PostgreSQL HA stack on top:
**Percona PPG (Percona PostgreSQL) + Patroni + etcd**, with optional pgBackRest
backups, HAProxy routing, and Percona Monitoring and Management (PMM).

> **Status (2026-05-31):** the OS-prep (`common`), `storage`, `pg_repos`, and `etcd`
> roles are implemented. A 3-node **etcd** cluster deploys and verifies green with
> etcd installed from the **Percona PPG** repository by default. The `storage` role
> formats and mounts the data disk on every database node (idempotent; skips
> etcd-only nodes automatically). The PostgreSQL / Patroni / backups / monitoring
> roles are still stubs. See **[What works today](#what-works-today)** for the exact state.
>
> Tested live on **Ubuntu 24.04** and **Rocky Linux** (the GCP fleet was rebuilt
> on Rocky on 2026-05-28 and the full pipeline ran green first-try, including a
> `changed=0` idempotency re-run).

---

## How it relates to the Terraform layer

```
terraform/clouds/<cloud>/  --(terraform apply)-->  ansible_inventory.yml
                                                   ansible_inventory.ini
                                                   credentials.json

                                                          |
                                                          | ansible/scripts/sync-inventory.sh <cloud>
                                                          v

ansible/inventory/<cloud>/  --(ansible-playbook)-->  configured PG fleet
```

The two layers communicate via three files only. Ansible never reads Terraform state.
See **[handoff.md](handoff.md)** for the full contract.

---

## What works today

| Phase | Playbook | Status |
|---|---|---|
| OS prep | `00_prepare.yml` (`common`) | **Implemented** — packages, timezone, locale, chrony/NTP, sysctl, ulimits. Debian/Ubuntu + RHEL/Rocky. |
| Storage | `00_prepare.yml` (`storage`) | **Implemented** — formats the data disk and mounts it at `/var/lib/postgresql`. Skips etcd-only nodes. |
| etcd | `10_etcd.yml` | **Implemented** — 3-node cluster, Percona repo by default (or upstream binary). |
| PostgreSQL + Patroni | `20_patroni.yml` | **Stub** |
| Backups | `30_backups.yml` | **Stub** |
| Monitoring | `40_monitoring.yml` | **Stub** |
| Verify | `99_verify.yml` | **Implemented for etcd** (member count + cluster health). Patroni/PG checks planned. |

`site.yml` runs the whole pipeline; today that means OS prep + a working etcd cluster
(the later phases are no-op stubs). The tested path is the three phases below.

---

## Quick start

Prerequisites:

- Terraform apply has succeeded for one of the cloud roots (see `terraform/doc/<cloud>.md`).
- `ansible-core >= 2.15` installed on your workstation.
- Python 3 on each target VM (Ubuntu/Debian/RHEL-family base images include this).

```bash
# 1. Install the Ansible collections used by the roles
cd ansible
ansible-playbook --version            # sanity check
ansible-galaxy install -r requirements.yml

# 2. Pull the latest Terraform artifacts into the Ansible inventory
./scripts/sync-inventory.sh gcp       # or aws, azure

## Note: if a passphrase is required for the ssh key, start the agent and add the key
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_rsa

## Verify the Ansible connectivity to the hosts
ansible -i inventory/gcp/hosts.yml all -m ping

# 3. OS prep, then bootstrap the etcd cluster
ansible-playbook -i inventory/gcp playbooks/00_prepare.yml
ansible-playbook -i inventory/gcp playbooks/10_etcd.yml

# 4. Verify the etcd cluster (3 members present, all healthy)
ansible-playbook -i inventory/gcp playbooks/99_verify.yml
```

`site.yml` runs the full (partly stubbed) pipeline in one shot:

```bash
ansible-playbook -i inventory/gcp playbooks/site.yml    # or aws, azure
```

Re-running any of these is safe — the roles are idempotent (a second `10_etcd.yml`
run reports `changed=0` and does **not** restart a healthy cluster).

---

## Manual inventory (servers from a system engineer, no Terraform)

If the VMs are provisioned outside Terraform — by a system engineer, an existing bare-metal pool, or another tool — skip `sync-inventory.sh` and write the inventory by hand.

### 1. Create the inventory directory

```bash
mkdir -p ansible/inventory/manual/group_vars/all
```

Use any name you like in place of `manual` (`bare-metal`, `prod`, etc.). The playbooks only care that `-i inventory/<name>` points at a directory with the expected files.

### 2. Write `hosts.yml`

This is the **only** inventory file you need. Do not create `hosts.ini` — it is a read-only compatibility artifact that `sync-inventory.sh` generates automatically from the YAML. Maintaining both by hand creates a sync hazard.

```yaml
# ansible/inventory/manual/hosts.yml
all:
  children:
    database_hosts:
      hosts:
        node1: {}
        node2: {}
        node3: {}
    etcd_cluster:
      hosts:
        node1: {}
        node2: {}
        node3: {}
  hosts:
    node1:
      ansible_host: 192.168.1.10          # public/jump IP used for SSH
      ansible_user: rocky
      ansible_ssh_private_key_file: /root/.ssh/id_rsa
      private_ip: 10.0.0.10               # internal IP — Patroni peers + etcd cluster URLs
      zone: dc1-rack-a                    # failover-domain label (any string)
      instance_type: bare-metal-large     # drives shared_buffers calculation
      data_disk_device: /dev/sdb          # block device the storage role will format + mount
      data_disk_size_gb: 500
    node2:
      ansible_host: 192.168.1.11
      ansible_user: rocky
      ansible_ssh_private_key_file: /root/.ssh/id_rsa
      private_ip: 10.0.0.11
      zone: dc1-rack-b
      instance_type: bare-metal-large
      data_disk_device: /dev/sdb
      data_disk_size_gb: 500
    node3:
      ansible_host: 192.168.1.12
      ansible_user: rocky
      ansible_ssh_private_key_file: /root/.ssh/id_rsa
      private_ip: 10.0.0.12
      zone: dc1-rack-c
      instance_type: bare-metal-large
      data_disk_device: /dev/sdb
      data_disk_size_gb: 500
```

Per-host variables:

| Variable | Required | Purpose |
|---|---|---|
| `ansible_host` | Yes | Reachable IP or hostname used for SSH |
| `ansible_user` | Yes | SSH login user |
| `ansible_ssh_private_key_file` | Yes | Path to the SSH private key on **your workstation** |
| `private_ip` | See below | Internal IP for etcd peer URLs and Patroni replication |
| `zone` | Yes | Failure-domain label (rack, AZ, datacenter — any string) |
| `instance_type` | Yes | Drives `shared_buffers` and `max_connections` calculations in role defaults |
| `data_disk_device` | Yes (DB nodes) | Block device the `storage` role will format and mount at `/var/lib/postgresql` |
| `data_disk_size_gb` | Yes (DB nodes) | Size of that device in GiB |

**When `private_ip` is required vs optional:**

The etcd role builds a cluster peer list that every node must agree on. It uses
`private_ip | default(ansible_host)`, so if `private_ip` is absent it falls back to
`ansible_host`. Whether that fallback is correct depends on your network:

- **Single-NIC host** (typical bare-metal): `ansible_host` IS the internal IP — omit
  `private_ip` and the fallback works correctly.
- **Multi-homed host** (cloud VM with a public IP for SSH and a separate internal IP for
  cluster traffic): `ansible_host` is the public IP. You must set `private_ip` to the
  internal IP, otherwise etcd and Patroni advertise a public address and cluster
  communication crosses the internet — or fails if firewall rules block the peer ports.

When Terraform provisions the VMs it knows both IPs definitively, so it always emits
`private_ip`. For a hand-written inventory, set it whenever `ansible_host` is a public
address that differs from the internal cluster address.

> **etcd-only nodes** (`etcd_cluster` members that are not in `database_hosts`) do not
> need `data_disk_device` or `data_disk_size_gb` — the `storage` role skips them.

### 3. Write `credentials.json`

```bash
cat > ansible/inventory/manual/credentials.json <<'EOF'
{
  "ssh_user": "rocky",
  "ssh_private_key_file": "/root/.ssh/id_rsa",
  "ssh_public_key_file": "/root/.ssh/id_rsa.pub",
  "provider": "bare-metal"
}
EOF
chmod 600 ansible/inventory/manual/credentials.json
```

This file is referenced via `vars_files:` in every play. Keep it mode `0600` — it is gitignored.

### 4. Write `group_vars/all/cloud.yml`

```yaml
# ansible/inventory/manual/group_vars/all/cloud.yml
provider: bare-metal
region: dc1

# Override any role default here, e.g.:
# timezone: America/New_York
# etcd_install_method: binary   # if the Percona repo is unreachable
```

### 5. Run the playbooks

Exactly the same commands as the Terraform path, just pointing at your directory:

```bash
cd ansible
ansible-galaxy install -r requirements.yml          # first time only

# Optional: if the SSH key has a passphrase
eval $(ssh-agent -s) && ssh-add /root/.ssh/id_rsa

ansible-playbook -i inventory/manual playbooks/00_prepare.yml
ansible-playbook -i inventory/manual playbooks/10_etcd.yml
ansible-playbook -i inventory/manual playbooks/99_verify.yml
```

---

## Configuration

### Where variables live

The framework loads variables from three places, lowest precedence first:

| Layer | Location | Use it for |
|---|---|---|
| **Role defaults** | `roles/<role>/defaults/main.yml` | Framework defaults a cloud may want to override — `timezone`/`locale` (`common`), `etcd_*` ports/scheme/`etcd_install_method` (`etcd`), `postgres_mount_point`/`postgres_data_disk_fs` (`storage`). |
| **Cross-play globals** | `playbooks/group_vars/all.yml`, `playbooks/group_vars/database_hosts.yml` | Values used across multiple plays — `cluster_name`, `pg_distribution`, `postgres_version`, feature toggles. |
| **Per-cloud overrides** | `inventory/<cloud>/group_vars/all/cloud.yml` | `provider`, `region`, and **overrides of any role default** for that cloud. Hand-edited; survives `sync-inventory.sh`. |
| **Per-host overrides** | `host_vars/<name>.yml` | Rare — e.g. an external etcd member's SSH details. |

> There is no top-level `ansible/group_vars/` — it was removed because Ansible only
> auto-loads `group_vars/` next to the inventory or the playbooks. **Precedence note:**
> `playbooks/group_vars/` *outranks* `inventory/<cloud>/group_vars/`, so to override a
> value per-cloud it must come from a **role default** (which inventory group_vars beat),
> not from `playbooks/group_vars/`.

### Storage (data disk)

The `storage` role runs as part of `00_prepare.yml` on every host in `database_hosts`.
It formats the attached data disk and mounts it — this is where PostgreSQL's
`data_directory` will live once the `postgresql` role lands.

**What it does:**

1. Skips the host entirely if `data_disk_device` is absent — etcd-only nodes that carry
   no data disk are left untouched.
2. Creates a filesystem on `data_disk_device` (default: `ext4`).
3. Creates the mount point directory if it does not exist.
4. Mounts the disk and writes a persistent `fstab` entry (mount options: `defaults,noatime`).

The role is **idempotent**: re-running `00_prepare.yml` on a host with a formatted,
mounted disk reports `changed=0` and does not reformat or remount.

**Variables** (role defaults, override per-cloud in `inventory/<cloud>/group_vars/all/cloud.yml`):

| Variable | Default | Notes |
|---|---|---|
| `postgres_mount_point` | `/var/lib/postgresql` | Mount path. PostgreSQL's `data_directory` will live under a version-specific subdirectory here once the `postgresql` role lands. |
| `postgres_data_disk_fs` | `ext4` | Filesystem type. `xfs` is also a good choice for high-WAL-volume workloads. |

**Per-host inputs** (set in the inventory, not as group vars):

| Variable | Notes |
|---|---|
| `data_disk_device` | Stable device path for the data disk — e.g. `/dev/disk/by-id/google-node1-data` (GCP), `/dev/disk/by-id/nvme-...` (AWS), `/dev/sdb` (bare-metal). Use a stable path, not `sdX`, which can shift on reboot. Omit on etcd-only nodes. |
| `data_disk_size_gb` | Informational only (not used by the role today; carried in inventory for future capacity checks). |

### Choosing the PostgreSQL version (and the repository it pulls from)

The `postgres_version` variable in `playbooks/group_vars/all.yml` is the single
source of truth for which Percona PPG repository every role installs from:

```yaml
postgres_version: 17          # PPG ships 16 and 17
```

`pg_repos` reads this and runs `percona-release setup -y ppg-<postgres_version>`,
which enables the matching Percona PPG repo on the host. Every consumer role
(`etcd` today; `postgresql`, `patroni`, `pgbackrest`, `pmm_client` when they
land) defaults to installing from this same repo.

**Per-role override.** Each consumer role exposes a `<role>_percona_repo`
variable defaulting to `pg_percona_repo` (i.e. `ppg-<postgres_version>`). Set it
in `inventory/<cloud>/group_vars/all/cloud.yml` to pin a specific component to a
different `ppg-<N>` than the cluster-wide version — useful, for example, to test
a new etcd from `ppg-17` while the rest of the stack stays on `ppg-16`:

```yaml
postgres_version: 16
etcd_percona_repo: ppg-17
```

Available override hooks: `etcd_percona_repo`, `postgresql_percona_repo`,
`patroni_percona_repo`, `pgbackrest_percona_repo`, `pmm_client_percona_repo`.

### etcd install source

etcd is installed from the **Percona PPG repository by default** — this is
automation for Percona customers, so etcd comes from Percona's curated,
security-maintained packages. The role exposes one switch (a role default,
override it per-cloud in `inventory/<cloud>/group_vars/all/cloud.yml`):

```yaml
etcd_install_method: package   # default — apt/yum from the Percona ppg-<version> repo
# etcd_install_method: binary  # alternative — upstream static release tarball
```

- **`package`** (default): delegates repo setup to `pg_repos`
  (`percona-release setup -y ppg-<postgres_version>`) and installs etcd from
  Percona's repo (`etcd etcd-server etcd-client` on Debian/Ubuntu;
  `etcd python3-python-etcd` + EPEL on RHEL/Rocky). etcd then runs under a
  systemd unit managed by this role, reading `/etc/etcd/etcd.conf.yaml`.
- **`binary`**: downloads the pinned upstream etcd release (`etcd_version`,
  default `3.5.30`) to `/usr/local/bin`. Useful for air-gapped or non-Percona
  environments.

Either way the cluster topology is derived from the `etcd_cluster` inventory
group and each host's `private_ip`. Useful etcd knobs (all role defaults, all
overridable):

| Variable | Default | Notes |
|---|---|---|
| `etcd_install_method` | `package` | `package` (Percona) or `binary` (upstream) |
| `etcd_percona_repo` | `{{ pg_percona_repo }}` (= `ppg-{{ postgres_version }}`) | Percona repo enabled for the package method |
| `etcd_client_port` / `etcd_peer_port` | `2379` / `2380` | |
| `etcd_scheme` | `http` | set `https` once you wire up certs |
| `etcd_version` | `3.5.30` | binary method only |

### Switching PostgreSQL distributions

By default the framework targets **Percona PPG**. Community **PGDG** is the
selectable alternative via `playbooks/group_vars/all.yml`:

```yaml
pg_distribution: pgdg
```

PPG is the better-tested path; the PGDG branch in `pg_repos` is not yet
implemented and the role will fail loudly if `pg_distribution: pgdg` is set.
(Per-cloud override of `pg_distribution` will become available once the
`postgresql` role moves it into role defaults — see the precedence note above.)

### Operating-system support

The implemented roles support **Debian/Ubuntu** and **RHEL/Rocky** (the `common` role
branches on `ansible_os_family` for package names, the chrony service name, and locale
handling; the `etcd` package method uses apt or yum/dnf accordingly). Both paths have
been tested live — the GCP fleet runs Rocky Linux and Ubuntu 24.04 has also been
verified end-to-end.

---

## What gets installed

| Tier | Components | State |
|---|---|---|
| OS prep | packages, timezone, locale, chrony/NTP, sysctl, ulimits | **Done** |
| Storage | mkfs + mount of the data disk at `/var/lib/postgresql` | **Done** |
| etcd | 3-node etcd cluster on the `etcd_cluster` group (Percona repo by default) | **Done** |
| PostgreSQL | PPG (or PGDG) packages, base config, `data_directory` under the mounted disk | Planned |
| Patroni | DCS-backed automatic failover, REST API on each node, systemd unit | Planned |
| Backups *(optional)* | pgBackRest, full + diff schedule, repo on cloud object storage | Planned |
| Routing *(optional)* | HAProxy with R/W and R/O endpoints driven by Patroni's REST API | Planned |
| Monitoring *(optional)* | PMM client registered against your PMM server | Planned |

Optional components are enabled via group vars (e.g. `pgbackrest_enabled: true`).

---

## Further reading

- **[handoff.md](handoff.md)** — the Terraform-to-Ansible file contract, in detail.
- **[runbook.md](runbook.md)** — day-2 operations (etcd checks today; switchover,
  replica reinit, rolling restart planned).
- `terraform/doc/README.md` — per-cloud provisioning guides.
- The `ansible/CLAUDE.md` file (gitignored) — internal design notes for contributors
  working with Claude Code sessions.
