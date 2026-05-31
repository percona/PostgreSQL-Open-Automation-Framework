# Day-2 operations runbook

Common operational procedures for a cluster deployed by this framework.

> **Status (2026-05-31):** the deploy/verify path is fully implemented — `99_verify.yml`
> checks etcd, **Patroni** (one leader + member count), PostgreSQL reachability,
> **HAProxy** routing, and **pgBackRest** (stanza check + a backup present). The cluster
> runs PostgreSQL + Patroni + etcd with optional HAProxy routing and pgBackRest backups.
> The *wrapper* ops playbooks under `playbooks/ops/` (switchover, replica reinit, rolling
> restart) are still **stubs** — for now drive those operations with `patronictl`
> directly, as shown below. Sections marked **[planned]** describe behavior the wrapper
> playbooks will add once implemented.

---

## Healthcheck — does the cluster look good?

```bash
cd ansible
ansible-playbook -i inventory/<cloud> playbooks/99_verify.yml
```

**Implemented today:**

- SSH + Python reachability on every host (`ping`).
- Storage mount check on `database_hosts`.
- PostgreSQL server binary present on `database_hosts`.
- etcd member list — asserts the member count equals the `etcd_cluster` group size,
  plus `etcdctl endpoint health --cluster` (fails if any member is unhealthy).
- Patroni — queries the REST `/cluster` API on a database host and asserts exactly
  **one leader** and that every `database_hosts` node is a member.
- HAProxy (when `haproxy_enabled`) — reads the stats CSV on each `haproxy` node and
  asserts the read-write (`primary`) and read-only (`standbys`) pools each have an UP
  backend.
- pgBackRest (when `pgbackrest_enabled`) — runs `pgbackrest check` on the repo host and
  asserts the stanza has at least one backup.

**[planned]** Add `pg_isready` per host and `pg_stat_replication` lag reporting per
standby.

Run it after any change. Run it as a cron from your monitoring host if you want a
cheap external healthcheck. Include the optional checks with
`-e haproxy_enabled=true -e pgbackrest_enabled=true`.

---

## Inspecting etcd directly

etcd is installed from the Percona PPG repo by default (`etcd_install_method: package`),
so `etcdctl` is on `PATH` (`/usr/bin/etcdctl`). On any etcd node:

```bash
export ETCDCTL_API=3
etcdctl --endpoints=http://127.0.0.1:2379 member list -w table
etcdctl --endpoints=http://127.0.0.1:2379 endpoint health --cluster
etcdctl --endpoints=http://127.0.0.1:2379 endpoint status -w table
```

The cluster runs under a systemd unit managed by the `etcd` role:

```bash
systemctl status etcd
journalctl -u etcd -f
```

To re-apply etcd config or recover a member, re-run the phase (it is idempotent and
will not restart a healthy cluster unless the config changed):

```bash
ansible-playbook -i inventory/<cloud> playbooks/10_etcd.yml
```

---

## Inspecting Patroni directly

`patronictl` is the source of truth for cluster state. On any database host:

```bash
sudo patronictl -c /etc/patroni/patroni.yml list      # topology: leader, replicas, lag
sudo patronictl -c /etc/patroni/patroni.yml show-config
sudo systemctl status percona-patroni
sudo journalctl -u percona-patroni -f
```

The Patroni REST API (port `8008`) is what HAProxy and `99_verify.yml` use:

```bash
curl -s http://127.0.0.1:8008/cluster | jq      # members + roles + lag
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8008/primary   # 200 only on the leader
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8008/replica   # 200 only on a replica
```

Re-running `20_patroni.yml` is safe: config changes **reload** (SIGHUP) without a
restart, and a healthy cluster is not disturbed.

---

## Inspecting HAProxy directly

When the optional HAProxy tier is deployed, each `haproxy` node exposes a stats UI:

```bash
# Stats UI in a browser:  http://<haproxy-ip>:7000/
curl -s 'http://127.0.0.1:7000/;csv' | column -s, -t | less   # backend up/down per pool
sudo systemctl status haproxy
```

Apps connect through HAProxy, not directly to PostgreSQL:

```bash
psql "host=<haproxy-ip> port=5000 ..."   # read-write — always lands on the leader
psql "host=<haproxy-ip> port=5001 ..."   # read-only  — load-balanced across replicas
```

On failover, HAProxy follows automatically: the new leader starts answering `200` on
`/primary`, the demoted node drops out of the `primary` pool. Re-run
`25_haproxy.yml` after changing the backend list; the config is `haproxy -c`-validated
and reloaded gracefully.

---

## Planned switchover (zero data loss)

A planned switchover promotes a chosen standby to primary, demoting the current
primary cleanly. Use this before OS patching, instance resizing, or zone
maintenance.

```bash
ansible-playbook -i inventory/<cloud> playbooks/ops/switchover.yml \
  -e target=node2
```

**[planned]** The playbook will:

1. Verify the target is a healthy synchronous (or low-lag asynchronous) standby.
2. Issue `patronictl switchover --candidate <target> --force` on the leader.
3. Wait for Patroni to confirm the new leader is accepting writes.
4. Re-run `99_verify.yml` automatically.

Patroni handles the actual promotion; this playbook is a safe wrapper that adds
pre-checks and post-checks.

---

## Reinitialize a broken replica

If a replica falls too far behind, gets a corrupted WAL, or otherwise needs to
re-base from the primary:

```bash
ansible-playbook -i inventory/<cloud> playbooks/ops/reinit_replica.yml \
  -e target=node3
```

**[planned]** The playbook will:

1. Confirm `target` is not the current leader.
2. Stop the local Patroni service.
3. Issue `patronictl reinit <cluster> <target>`.
4. Wait for Patroni to mark the node as `running` again.
5. Confirm replication lag has dropped below the configured threshold.

This is destructive on the target node (the data directory is wiped and rebuilt
from the primary). The playbook prompts for confirmation by default; pass
`-e confirm=yes` to skip the prompt in automation.

---

## Rolling restart

Restart every PostgreSQL instance in the cluster one at a time, with switchover
inserted before the leader is restarted.

```bash
ansible-playbook -i inventory/<cloud> playbooks/ops/rolling_restart.yml
```

**[planned]** The playbook will:

1. Restart standbys first, one at a time, waiting for each to rejoin before
   moving on.
2. When only the leader remains, perform a switchover to a healthy standby.
3. Restart the former leader.
4. Run `99_verify.yml`.

Use this after configuration changes that require a PG restart (e.g.
`shared_buffers` change, extension load).

---

## Reapply configuration to a single host

For changes that don't need a restart (most `postgresql.conf` parameters via
`pg_reload_conf()`, sysctl tweaks, package upgrades):

```bash
ansible-playbook -i inventory/<cloud> playbooks/site.yml \
  --limit node2 \
  --tags postgresql,patroni
```

`--limit` and `--tags` are stock Ansible — no playbook changes needed to support them.

---

## Adding a new node

> **[planned]** Full procedure pending implementation. The intended flow:

1. Add the node to `vms` and `database_hosts` in `terraform/clouds/<cloud>/terraform.tfvars`.
2. `terraform apply` — provisions the new VM, regenerates the inventory.
3. `ansible/scripts/sync-inventory.sh <cloud>` — pulls the updated inventory.
4. `ansible-playbook -i inventory/<cloud> playbooks/site.yml --limit <new-node>` —
   runs the full pipeline against the new host only.
5. Patroni will detect the new member and start replicating from the leader.
6. `99_verify.yml` should pass.

---

## Removing a node

> **[planned]** The intended flow:

1. Ensure the node is **not** the current leader (`patronictl switchover` if it is).
2. Drain it from any HAProxy / load balancer pools.
3. Run `patronictl remove <cluster>` against the node.
4. Remove the entry from `vms` and `database_hosts` in `terraform.tfvars`.
5. `terraform apply` — destroys the VM and regenerates the inventory.
6. `ansible/scripts/sync-inventory.sh <cloud>`.

The framework does not yet automate steps 1-3; do them manually before the
Terraform destroy.

---

## Backup & restore

pgBackRest uses a **dedicated repository host** (the `backup_server` group), so backup
and `info` commands run **on that host** (not the DB nodes), as the `postgres` user.
The stanza is named after the cluster (`cluster_name`, default `poaf`). Enable it with
`-e pgbackrest_enabled=true` on `30_backups.yml` (or set it in group vars).

```bash
# On the backup server (repository host):
sudo -u postgres pgbackrest --stanza=poaf info                    # backups + WAL archive range
sudo -u postgres pgbackrest --stanza=poaf check                   # config + archiving healthy?
sudo -u postgres pgbackrest --stanza=poaf --type=full backup      # ad-hoc full
sudo -u postgres pgbackrest --stanza=poaf --type=diff backup      # ad-hoc diff
```

Scheduled backups run from `systemd` timers on the repo host (full on Sundays, diff
the rest of the week by default — see `pgbackrest_backups`):

```bash
systemctl list-timers 'pgbackrest-*'
systemctl status pgbackrest-full-backup.timer pgbackrest-diff-backup.timer
```

Continuous WAL archiving is driven by the primary's `archive_command`
(`pgbackrest --stanza=poaf archive-push %p`), set in Patroni's DCS config. `archive_mode`
was enabled with a one-time rolling restart when the role first ran.

For **restore** / point-in-time recovery, refer to the
[pgBackRest user guide](https://pgbackrest.org/user-guide.html) — this framework
configures pgBackRest but does not wrap the restore commands, since restore is
deliberately a manual operation that should be performed with care. Note that in a
Patroni cluster a restore is coordinated through Patroni (e.g. `patronictl reinit`, or
restoring on the leader with the cluster stopped), not by starting PostgreSQL directly.

---

## When in doubt

- `99_verify.yml` is cheap and safe — run it any time.
- Patroni's `patronictl` is the source of truth for cluster state; trust it over
  Ansible's view.
- The inventory is regenerated by Terraform, not edited by hand. If something looks
  wrong in `ansible/inventory/<cloud>/hosts.yml`, the fix lives in `terraform.tfvars`,
  not in the inventory file itself.
