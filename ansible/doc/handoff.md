# Terraform -> Ansible handoff

This page is the **complete contract** between the two layers of
PostgreSQL-Open-Automation-Framework. If you understand this page, you understand
how the framework's two halves talk to each other.

---

## The contract in one sentence

> After `terraform apply`, three files exist next to the cloud root. A small script
> copies them into `ansible/inventory/<cloud>/`. Playbooks read those files and
> nothing else.

There is **no runtime coupling** — Ansible never reads Terraform state, never imports
the TF state schema, and does not need cloud-provider credentials. Everything that
crosses the boundary is a plain file.

---

## What Terraform emits

After a successful `terraform apply` inside `terraform/clouds/<cloud>/`, three files
exist alongside the cloud root:

| File | Mode | Tracked in git? | Purpose |
|---|---|---|---|
| `ansible_inventory.yml` | `0644` | no (gitignored) | Primary inventory consumed by playbooks. YAML format with nested per-host vars. |
| `ansible_inventory.ini` | `0644` | no (gitignored) | Compatibility inventory for ad-hoc `ansible host -m ping` style commands. |
| `credentials.json`      | `0600` | no (gitignored) | SSH user, SSH key paths, provider name. Loaded by playbooks via `vars_files`. |

### `ansible_inventory.yml` shape

```yaml
all:
  vars:
    ansible_python_interpreter: /usr/bin/python3
  children:
    database_hosts:
      hosts:
        node1:
          ansible_host: 34.10.20.30        # public IP, used for SSH
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          private_ip: 10.128.0.5           # used for Patroni replication, etcd peers
          zone: us-central1-a
          instance_type: n2-standard-4
          data_disk_size_gb: 200
          data_disk_device: /dev/disk/by-id/google-node1-data
        node2: { ... }
        node3: { ... }
    etcd_cluster:
      hosts:
        node1: {}   # same hosts referenced again; vars merge from database_hosts
        node2: {}
        node3: {}
```

External etcd members (names in `etcd_hosts` that are not in `vms`, i.e. pre-existing
infrastructure) appear with `ansible_host` set to the member name itself and **no**
`data_disk_*` / `private_ip` / `zone` / `instance_type` vars. Operators are expected
to add those via `host_vars/<name>.yml` if needed.

### `credentials.json` shape

```json
{
  "provider": "gcp",
  "ssh_user": "ubuntu",
  "ssh_private_key_file": "/home/jdoe/.ssh/id_rsa",
  "ssh_public_key_file":  "/home/jdoe/.ssh/id_rsa.pub",
  "generated_at": "2026-05-26T18:42:10Z"
}
```

These fields duplicate what's already inline in the inventory's `ansible_*` vars, but
loading them via `vars_files` exposes them as plain top-level vars (`ssh_user`,
`ssh_private_key_file`) — useful for tasks that need the key path or username outside
of an SSH connection (e.g. configuring `authorized_keys` on additional users).

---

## How Ansible consumes it

### Step 1 — sync the artifacts into the Ansible tree

```bash
ansible/scripts/sync-inventory.sh gcp
```

This copies the three files from `terraform/clouds/gcp/` into `ansible/inventory/gcp/`:

```
ansible/inventory/gcp/
├── hosts.yml          <- ansible_inventory.yml
├── hosts.ini          <- ansible_inventory.ini
├── credentials.json   <- credentials.json (preserved as mode 0600)
└── group_vars/all/
    └── cloud.yml      <- hand-edited; survives re-syncs
```

The script is idempotent: re-running it overwrites the three synced files but leaves
`group_vars/` and `host_vars/` untouched.

### Step 2 — run playbooks against the synced inventory

```bash
ansible-playbook -i inventory/gcp playbooks/site.yml
```

Every playbook starts with:

```yaml
- hosts: all
  become: true
  vars_files:
    - "{{ inventory_dir }}/credentials.json"   # ssh_user, ssh_private_key_file, ...
  roles:
    - { role: common }
```

`{{ inventory_dir }}` resolves to `ansible/inventory/gcp/` (because of the `-i`
flag), so `credentials.json` is loaded automatically without naming the cloud
anywhere in the playbook. This is how the same `site.yml` works against any cloud.

> **If you run with `-i hosts.yml` directly** (pointing at a file, not a directory),
> `{{ inventory_dir }}` resolves to the file's parent — still correct as long as
> `credentials.json` sits next to it. Pointing `-i` at a different location without
> `credentials.json` will fail with "could not find file".

---

## Why this shape (not dynamic inventory)

Three alternatives were considered and rejected:

| Option | Why not |
|---|---|
| **Dynamic inventory via `cloud.terraform.terraform_state`** | Ansible host would need read access to TF state (local file or remote backend credentials). Pins Ansible to a TF state schema. Breaks the clean per-cloud isolation. |
| **Cloud-native dynamic plugins** (`amazon.aws.aws_ec2`, etc.) | Each cloud has different auth + tag conventions; loses the etcd/db tiering and `data_disk_device` that TF computes; effectively re-implements the cloud modules' logic in Ansible. |
| **INI only (status quo before YAML)** | Per-host vars stay flat — awkward for richer Patroni/etcd metadata like nested topology hints. |

The chosen approach (rendered YAML + INI + credentials.json) decouples runtime,
works offline, fits naturally with CI, and keeps sensitive data isolated to a single
0600 file.

---

## What you must add by hand

The contract above covers everything Terraform can know. A few things only the
operator knows — these live in role defaults, `playbooks/group_vars/`, the per-cloud
`inventory/<cloud>/group_vars/all/cloud.yml`, or `host_vars/`. (There is no top-level
`ansible/group_vars/`; see the Ansible README's *Where variables live* section.)

| Setting | Where | Default |
|---|---|---|
| `etcd_install_method: package\|binary` | role default; override per-cloud in `cloud.yml` | `package` (Percona repo) |
| `pg_distribution: percona\|pgdg` | `playbooks/group_vars/all.yml` | `percona` |
| `postgres_version` | `playbooks/group_vars/all.yml` | latest supported PDPG |
| `pgbackrest_enabled: true` and repo config | `playbooks/group_vars/all.yml` | disabled |
| PMM server URL + token | `playbooks/group_vars/all.yml` (or vault) | disabled |
| External etcd member SSH details | `host_vars/<name>.yml` | — |

---

## Troubleshooting the handoff

| Symptom | Likely cause |
|---|---|
| `ansible-playbook` says *"Could not parse inventory"* | `sync-inventory.sh` was not run after the last `terraform apply`. Re-sync. |
| Hosts show up but `ssh: permission denied` | `credentials.json` SSH key path is wrong — open the file and check `ssh_private_key_file` resolves on your workstation. |
| `private_ip is undefined` for an etcd member | That host is an **external** etcd member (not in `vms`). Add `private_ip` via `host_vars/<name>.yml`. |
| Data disk not mounted on a node | Inventory's `data_disk_device` doesn't match what the kernel sees. On older AWS Xen instances override to `/dev/xvdf` in `host_vars/`. See `terraform/CLAUDE.md` for the per-cloud device-path rules. |
