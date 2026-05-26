# PostgreSQL-Open-Automation-Framework

An open framework for provisioning the infrastructure and (eventually)
configuring the software stack behind a PostgreSQL deployment, across the
major public clouds.

The current scope is **VM provisioning + Ansible inventory generation**.
Downstream Ansible playbooks consume the generated inventory to install and
configure PostgreSQL on the provisioned fleet.

## Layout

```
terraform/                  # Multi-cloud VM provisioner
├── clouds/{gcp,aws,azure}/ # One Terraform root per cloud
├── modules/                # Reusable cloud + inventory modules
├── doc/                    # Per-cloud setup guides
└── scripts/validate.sh     # fmt / init / validate across all roots
```

Each cloud is an independent Terraform root — you only need credentials for
the cloud whose directory you are working in. State files do not cross
providers.

## Getting started

1. Pick a cloud (`gcp`, `aws`, or `azure`) and read the matching guide in
   [terraform/doc/](terraform/doc/).
2. `cd terraform/clouds/<cloud>/` and copy `terraform.tfvars.example` to
   `terraform.tfvars`. Fill in your project / region / SSH key paths.
3. `terraform init && terraform validate && terraform plan -out=tfplan`
4. `terraform apply tfplan` — on success an `ansible_inventory.ini` (and
   a sensitive `credentials.json`) are written next to the cloud root.

See [terraform/doc/README.md](terraform/doc/README.md) for the index of
per-provider guides.

## Status

This is an early, in-development project. The Terraform layer is functional
across GCP, AWS and Azure. The Ansible layer is not yet published.

## License

To be determined — open the [issues tab](https://github.com/percona/PostgreSQL-Open-Automation-Framework/issues)
to discuss.
