# inventory/

One subdirectory per cloud. Populated by `../scripts/sync-inventory.sh <cloud>`,
which copies the three artifacts emitted by `terraform apply` into the matching
subdir.

## What's synced (regenerated; do not hand-edit)

These files are overwritten by every `sync-inventory.sh` run and are gitignored:

```
inventory/<cloud>/hosts.yml         <- terraform/clouds/<cloud>/ansible_inventory.yml
inventory/<cloud>/hosts.ini         <- terraform/clouds/<cloud>/ansible_inventory.ini
inventory/<cloud>/credentials.json  <- terraform/clouds/<cloud>/credentials.json  (mode 0600)
```

## What's hand-edited (committed)

```
inventory/<cloud>/group_vars/all/cloud.yml   <- per-cloud overrides (provider, region, pg_distribution)
inventory/<cloud>/host_vars/<name>.yml       <- rare per-host overrides
```

`sync-inventory.sh` leaves these alone.

## How playbooks find credentials

Every playbook loads `credentials.json` via:

```yaml
vars_files:
  - "{{ inventory_dir }}/credentials.json"
```

`{{ inventory_dir }}` resolves to `inventory/<cloud>/` when you run
`ansible-playbook -i inventory/<cloud> playbooks/site.yml`. There is no hard-coded
cloud name in any playbook — the same `site.yml` works on every cloud.
