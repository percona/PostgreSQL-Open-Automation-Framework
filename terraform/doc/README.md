# Cloud Provider Setup Guides

One markdown per provider. Read the one matching the directory you'll be
running `terraform` from.

| File              | Provider | CLI       | `cd` into…           | Default region/zone        |
|-------------------|----------|-----------|-----------------------|----------------------------|
| [gcp.md](gcp.md)     | Google Cloud         | `gcloud`  | `clouds/gcp/`   | `us-central1` / `us-central1-a` |
| [aws.md](aws.md)     | Amazon Web Services  | `aws`     | `clouds/aws/`   | `us-east-1`                |
| [azure.md](azure.md) | Microsoft Azure      | `az`      | `clouds/azure/` | `East US`                  |

Each guide covers the same four things, in this order:

1. Install the CLI.
2. Log in (interactive **and** non-interactive / CI-friendly paths).
3. Verify connectivity to the provider API.
4. Wire the credentials into the matching `clouds/<X>/terraform.tfvars` so
   `terraform apply` succeeds.

Each guide also has a **Section 5 — Switching to Rocky Linux 8 / 9** that
shows the tfvars-only override needed to boot Rocky instead of the default
Ubuntu 22.04. The override is image + `ssh_user` on GCP and AWS; on Azure
it additionally requires `azure_image_plan` and a one-time
`az vm image terms accept`, because Rocky on Azure ships through the
Marketplace.

Each cloud is a fully independent Terraform root — you only need credentials
for the cloud whose directory you're working in.
