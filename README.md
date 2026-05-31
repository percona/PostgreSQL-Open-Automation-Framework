# PostgreSQL-Open-Automation-Framework

An open framework for provisioning the infrastructure and (eventually)
configuring the software stack behind a PostgreSQL deployment, across the
major public clouds.

The Terraform layer (**VM provisioning + Ansible inventory generation**) is
functional across all three clouds. The Ansible layer consumes that inventory to
deploy a PostgreSQL HA stack — **Percona PostgreSQL + Patroni + etcd**, with optional
**HAProxy** connection routing and **pgBackRest** backups (continuous WAL archiving +
scheduled backups to a dedicated repository host) — all installed from the Percona
PostgreSQL repository. The full stack has been deployed and verified end-to-end on a
6-node Azure fleet (3 database/etcd nodes + 2 HAProxy + 1 backup server). Monitoring
(PMM) is next.

## Layout

```
terraform/                  # Multi-cloud VM provisioner
├── clouds/{gcp,aws,azure}/ # One Terraform root per cloud
├── modules/                # Reusable cloud + inventory modules
├── doc/                    # Per-cloud setup guides
└── scripts/validate.sh     # fmt / init / validate across all roots

ansible/                    # Percona PostgreSQL + Patroni + etcd configurator
├── inventory/{gcp,aws,azure}/  # Populated from terraform/ via scripts/sync-inventory.sh
├── roles/                  # common, storage, pg_repos, postgresql, etcd, patroni, …
├── playbooks/              # site.yml + phased + day-2 ops
└── doc/                    # User-facing docs (README, handoff contract, runbook)
```

Each cloud is an independent Terraform root — you only need credentials for
the cloud whose directory you are working in. State files do not cross
providers. Ansible consumes the inventory + credentials Terraform emits;
it never reads Terraform state directly. See
[ansible/doc/handoff.md](ansible/doc/handoff.md) for the full contract.

## Getting started

1. Pick a cloud (`gcp`, `aws`, or `azure`) and read the matching guide in
   [terraform/doc/](terraform/doc/).
2. `cd terraform/clouds/<cloud>/` and copy `terraform.tfvars.example` to
   `terraform.tfvars`. Fill in your project / region / SSH key paths.
3. `terraform init && terraform validate && terraform plan -out=tfplan`
4. `terraform apply tfplan` — on success `ansible_inventory.yml`,
   `ansible_inventory.ini`, and a sensitive `credentials.json` are written
   next to the cloud root.

See [terraform/doc/README.md](terraform/doc/README.md) for the index of
per-provider guides, and [ansible/doc/README.md](ansible/doc/README.md) for
the Ansible layer.

## Status

This is an early, in-development project.

- **Terraform layer:** functional across GCP, AWS and Azure. Renders both YAML
  (primary) and INI (compat) Ansible inventory plus a sensitive
  `credentials.json` sidecar after every `terraform apply`.
- **Ansible layer:** the PostgreSQL HA stack is implemented and deploys + verifies
  green — OS prep (`common`), `storage`, `pg_repos`, a 3-node **etcd** cluster,
  **PostgreSQL** + **Patroni** (leader-first bootstrap, automatic failover), and
  optional **HAProxy** routing (read-write on `:5000`, read-only on `:5001`) and
  optional **pgBackRest** backups (dedicated repository host over SSH, continuous WAL
  archiving, scheduled full/diff backups). All packages come from the **Percona
  Distribution for PostgreSQL** repo by default, on Debian/Ubuntu and RHEL/Rocky.
  Tested live end-to-end on a 6-node Azure Rocky 9 fleet (and earlier on Ubuntu). The
  **PMM** monitoring role is still a stub. See [ansible/doc/README.md](ansible/doc/README.md)
  for the current state and usage — contributions welcome.

## License

To be determined — open the [issues tab](https://github.com/percona/PostgreSQL-Open-Automation-Framework/issues)
to discuss.
