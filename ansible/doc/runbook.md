# Day-2 operations runbook

Common operational procedures for a cluster deployed by this framework.

> **Status:** the playbooks referenced below are **planned, not yet implemented**.
> This document records the intended procedures so they're agreed before any code
> lands. Sections marked **[planned]** describe behavior the playbooks will provide
> once written.

---

## Healthcheck — does the cluster look good?

```bash
cd ansible
ansible-playbook -i inventory/<cloud> playbooks/99_verify.yml
```

**[planned]** This playbook will:

- Run `patronictl -c /etc/patroni/patroni.yml list` on the leader.
- Check `pg_isready` on every database host.
- Report `pg_stat_replication` lag for each standby.
- List etcd cluster members and confirm a healthy quorum.
- Fail loudly if any host is unreachable, any standby is more than N seconds behind,
  or etcd has lost quorum.

Run it after any change. Run it as a cron from your monitoring host if you want a
cheap external healthcheck.

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

> **[planned]** Once `pgbackrest_enabled: true` is set in `group_vars/database_hosts.yml`
> and the `30_backups.yml` playbook has been run:

```bash
# On any database host (typically the leader):
sudo -u postgres pgbackrest --stanza=main info
sudo -u postgres pgbackrest --stanza=main --type=full backup     # ad-hoc full
sudo -u postgres pgbackrest --stanza=main --type=diff backup     # ad-hoc diff
```

Scheduled backups run from systemd timers configured by the `pgbackrest` role.

For restore procedures, refer to the
[pgBackRest user guide](https://pgbackrest.org/user-guide.html) — this framework
configures pgBackRest but does not wrap the restore commands, since restore is
deliberately a manual operation that should be performed with care.

---

## When in doubt

- `99_verify.yml` is cheap and safe — run it any time.
- Patroni's `patronictl` is the source of truth for cluster state; trust it over
  Ansible's view.
- The inventory is regenerated by Terraform, not edited by hand. If something looks
  wrong in `ansible/inventory/<cloud>/hosts.yml`, the fix lives in `terraform.tfvars`,
  not in the inventory file itself.
