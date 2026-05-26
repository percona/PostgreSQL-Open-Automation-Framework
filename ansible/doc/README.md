# Ansible layer

The Ansible layer of **PostgreSQL-Open-Automation-Framework** takes the VM fleet
provisioned by Terraform and installs a production-style PostgreSQL HA stack on top:
**Percona Distribution for PostgreSQL + Patroni + etcd**, with optional pgBackRest
backups, HAProxy routing, and Percona Monitoring and Management (PMM).

> **Status:** design and scaffold published; roles and playbooks are not yet
> implemented. This directory contains the documentation that will guide that work.
> Track progress at the project repo.

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

## Quick start (once implementation lands)

Prerequisites:

- Terraform apply has succeeded for one of the cloud roots (see `terraform/doc/<cloud>.md`).
- `ansible-core >= 2.15` installed on your workstation.
- Python 3 on each target VM (Ubuntu/Debian/RHEL-family base images include this).

```bash
# 1. Install Ansible collections used by the roles
cd ansible
ansible-playbook --version            # sanity check
ansible-galaxy install -r requirements.yml

# 2. Pull the latest Terraform artifacts into the Ansible inventory
./scripts/sync-inventory.sh gcp       # or aws, azure

# 3. Run the full pipeline
ansible-playbook -i inventory/gcp playbooks/site.yml

# 4. Verify the cluster
ansible-playbook -i inventory/gcp playbooks/99_verify.yml
```

You can run any phase in isolation:

```bash
ansible-playbook -i inventory/gcp playbooks/10_etcd.yml
ansible-playbook -i inventory/gcp playbooks/20_patroni.yml
```

---

## Configuration

### Cross-cloud defaults — `ansible/group_vars/`

| File | What it sets |
|---|---|
| `all.yml` | `postgres_version`, `pg_distribution` (default `percona`), `timezone`, `locale` |
| `database_hosts.yml` | `data_dir`, `wal_dir`, PG memory/connection defaults |
| `etcd_cluster.yml` | etcd client/peer ports, scheme |

### Cloud-specific overrides — `ansible/inventory/<cloud>/group_vars/all/cloud.yml`

| Key | What it sets |
|---|---|
| `provider` | `gcp` / `aws` / `azure` |
| `region` | cloud region (informational) |
| `pg_distribution` | override the global default if you want PGDG instead of PDPG on this cloud |

### Switching PostgreSQL distributions

By default the framework installs **Percona Distribution for PostgreSQL**. To use
community PGDG instead, set in `group_vars/all.yml` (cross-cloud) or in
`inventory/<cloud>/group_vars/all/cloud.yml` (per-cloud):

```yaml
pg_distribution: pgdg
```

PDPG is the better-tested path; PGDG is supported for compatibility.

### Per-host overrides — `host_vars/<name>.yml`

Use sparingly. Most facts the playbooks need (IPs, instance type, disk device) come
from the synced inventory automatically. Common reasons to add a `host_vars/` file:

- An **external etcd member** (a hostname listed in `etcd_hosts` but not provisioned
  by Terraform) — needs `ansible_host` and possibly `ansible_user`.
- A node with a non-standard data disk path that the cloud module couldn't infer.

---

## What gets installed

| Tier | Components |
|---|---|
| OS prep | packages, sysctl, ulimits, users, NTP |
| Storage | mkfs.ext4 + mount of the data disk at `/var/lib/postgresql` |
| etcd | 3-node etcd cluster on the `etcd_cluster` group |
| PostgreSQL | PDPG (or PGDG) packages, base config, `data_directory` under the mounted disk |
| Patroni | DCS-backed automatic failover, REST API on each node, systemd unit |
| Backups *(optional)* | pgBackRest, full + diff schedule, repo on cloud object storage |
| Routing *(optional)* | HAProxy with R/W and R/O endpoints driven by Patroni's REST API |
| Monitoring *(optional)* | PMM client registered against your PMM server |

Optional components are enabled via group vars (e.g. `pgbackrest_enabled: true`).

---

## Further reading

- **[handoff.md](handoff.md)** — the Terraform-to-Ansible file contract, in detail.
- **[runbook.md](runbook.md)** — day-2 operations (switchover, replica reinit, rolling restart).
- `terraform/doc/README.md` — per-cloud provisioning guides.
- The `ansible/CLAUDE.md` file (gitignored) — internal design notes for contributors
  working with Claude Code sessions.
