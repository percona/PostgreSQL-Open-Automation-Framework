# Ansible layer

The Ansible layer of **PostgreSQL-Open-Automation-Framework** takes the VM fleet
provisioned by Terraform and installs a production-style PostgreSQL HA stack on top:
**Percona Distribution for PostgreSQL + Patroni + etcd**, with optional pgBackRest
backups, HAProxy routing, and Percona Monitoring and Management (PMM).

> **Status (2026-05-27):** the OS-prep (`common`) and `etcd` roles are implemented. A
> 3-node **etcd** cluster — the distributed store Patroni uses — deploys and verifies
> green, with etcd installed from the **Percona Distribution for PostgreSQL (PDPG)**
> repository by default. The PostgreSQL / Patroni / backups / monitoring roles are
> still stubs. See **[What works today](#what-works-today)** for the exact state.
>
> Tested live on **Ubuntu 24.04**. The **RHEL / Rocky** code paths are written but not
> yet verified on a live host.

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
| Storage | `00_prepare.yml` (`storage`) | **Stub** — defaults are in place; the mkfs/mount tasks are not written yet. |
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

# 3. OS prep, then bootstrap the etcd cluster
ansible-playbook -i inventory/gcp playbooks/00_prepare.yml
ansible-playbook -i inventory/gcp playbooks/10_etcd.yml

# 4. Verify the etcd cluster (3 members present, all healthy)
ansible-playbook -i inventory/gcp playbooks/99_verify.yml
```

`site.yml` runs the full (partly stubbed) pipeline in one shot:

```bash
ansible-playbook -i inventory/gcp playbooks/site.yml
```

Re-running any of these is safe — the roles are idempotent (a second `10_etcd.yml`
run reports `changed=0` and does **not** restart a healthy cluster).

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

### etcd install source

etcd is installed from the **Percona PDPG repository by default** — this is automation
for Percona customers, so etcd comes from Percona's curated, security-maintained
packages. The role exposes one switch (a role default, override it per-cloud in
`inventory/<cloud>/group_vars/all/cloud.yml`):

```yaml
etcd_install_method: package   # default — apt/yum from the Percona ppg-<version> repo
# etcd_install_method: binary  # alternative — upstream static release tarball
```

- **`package`** (default): runs `percona-release setup ppg-<postgres_version>` and
  installs etcd from Percona's repo (`etcd etcd-server etcd-client` on Debian/Ubuntu;
  `etcd python3-python-etcd` + EPEL on RHEL/Rocky). etcd then runs under a systemd unit
  managed by this role, reading `/etc/etcd/etcd.conf.yaml`.
- **`binary`**: downloads the pinned upstream etcd release (`etcd_version`, default
  `3.5.30`) to `/usr/local/bin`. Useful for air-gapped or non-Percona environments.

Either way the cluster topology is derived from the `etcd_cluster` inventory group and
each host's `private_ip`. Useful etcd knobs (all role defaults, all overridable):

| Variable | Default | Notes |
|---|---|---|
| `etcd_install_method` | `package` | `package` (Percona) or `binary` (upstream) |
| `etcd_percona_repo` | `ppg-{{ postgres_version }}` | Percona repo enabled for the package method |
| `etcd_client_port` / `etcd_peer_port` | `2379` / `2380` | |
| `etcd_scheme` | `http` | set `https` once you wire up certs |
| `etcd_version` | `3.5.30` | binary method only |

### Switching PostgreSQL distributions

By default the framework targets **Percona Distribution for PostgreSQL**. To select
community PGDG instead, set in `playbooks/group_vars/all.yml`:

```yaml
pg_distribution: pgdg
```

PDPG is the better-tested path; PGDG is supported for compatibility. (Per-cloud override
of `pg_distribution` will become available once the `pg_repos`/`postgresql` roles move it
into role defaults — see the precedence note above.)

### Operating-system support

The implemented roles support **Debian/Ubuntu** and **RHEL/Rocky** (the `common` role
branches on `ansible_os_family` for package names, the chrony service name, and locale
handling; the `etcd` package method uses apt or yum/dnf accordingly). Only the
Debian/Ubuntu path is currently tested on live hosts.

---

## What gets installed

| Tier | Components | State |
|---|---|---|
| OS prep | packages, timezone, locale, chrony/NTP, sysctl, ulimits | **Done** |
| Storage | mkfs + mount of the data disk at `/var/lib/postgresql` | Planned (defaults only) |
| etcd | 3-node etcd cluster on the `etcd_cluster` group (Percona repo by default) | **Done** |
| PostgreSQL | PDPG (or PGDG) packages, base config, `data_directory` under the mounted disk | Planned |
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
