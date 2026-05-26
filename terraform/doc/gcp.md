# Google Cloud (GCP) Setup

Use this guide when running `terraform` from `clouds/gcp/`.

The Terraform module uses `google_compute_instance` + `google_compute_disk`.
It authenticates through the standard **Application Default Credentials (ADC)**
chain, so anything that populates ADC works.

---

## 1. Install the `gcloud` CLI

### Linux (Debian / Ubuntu)
```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y google-cloud-cli
```

### Linux (RHEL / CentOS / Fedora)
```bash
sudo tee /etc/yum.repos.d/google-cloud-sdk.repo <<EOF
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
sudo dnf install -y google-cloud-cli
```

### macOS
```bash
brew install --cask google-cloud-sdk
```

### Universal installer (any OS)
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL   # restart shell so PATH picks up gcloud
```

### Verify the install
```bash
gcloud --version
# Should print: Google Cloud SDK 4xx.0.0 ...
```

---

## 2. Log in

You have two practical options. **Pick one.**

### Option A — Interactive user login (best for laptops / dev)
```bash
gcloud auth login                          # browser opens
gcloud auth application-default login      # writes ADC for SDKs / Terraform
gcloud config set project <YOUR_PROJECT_ID>
```

The second command is the important one for Terraform — it writes a JSON file
to `~/.config/gcloud/application_default_credentials.json` which the Terraform
`google` provider auto-picks up.

### Option B — Service-account key file (best for CI / non-interactive)
1. Create a service account in the GCP console with the roles:
   `Compute Admin`, `Service Account User`, `Storage Admin` (if your image
   bucket is private).
2. Generate and download a JSON key.
3. Point ADC at it:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/secure/path/to/sa-key.json"
   gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
   gcloud config set project <YOUR_PROJECT_ID>
   ```

> ⚠️  Never commit the service-account JSON. Store it outside the repo and
> reference it via the env var.

---

## 3. Verify connectivity

Run these from the same shell you'll run Terraform in. Each should succeed
**without** an interactive prompt.

```bash
# 3.1  CLI sees the right account and project
gcloud auth list
gcloud config list

# 3.2  ADC file exists and is readable
gcloud auth application-default print-access-token >/dev/null \
  && echo "ADC OK"

# 3.3  Compute API is enabled and reachable
gcloud compute zones list --limit=5

# 3.4  You have permission to create instances and disks.
# Cloud Resource Manager's testIamPermissions API tells you which of the
# requested permissions are actually granted on the project. There's no
# direct `gcloud` subcommand for this, so call the REST endpoint:
PROJECT_ID=<YOUR_PROJECT_ID>
curl -s -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{"permissions":["compute.instances.create","compute.disks.create"]}' \
  "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}:testIamPermissions"
# Expected output (both permissions present):
#   {"permissions":["compute.instances.create","compute.disks.create"]}
# An empty response ({}) or a shorter list means you're missing one or both.
```

If 3.3 fails with `Compute Engine API has not been used in project …`, enable
it once:
```bash
gcloud services enable compute.googleapis.com
```

---

## 4. Wire it into the Terraform project

In `clouds/gcp/terraform.tfvars`:
```hcl
gcp_project = "your-gcp-project-id"   # REQUIRED
gcp_region  = "us-central1"           # optional, this is the default
gcp_zone    = "us-central1-a"         # optional, this is the default
gcp_image   = "ubuntu-os-cloud/ubuntu-2204-lts"  # optional
```

In your shell (only if you used **Option B** above):
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/secure/path/to/sa-key.json"
```

Then:
```bash
cd clouds/gcp
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## 5. Switching to Rocky Linux 8 / 9

The default boot image is Ubuntu 22.04. To run Rocky Linux instead, override
two variables in `clouds/gcp/terraform.tfvars` — no source changes required.

```hcl
# Rocky Linux 9 (replace with rocky-linux-8 for 8.x)
gcp_image = "rocky-linux-cloud/rocky-linux-9"
ssh_user  = "rocky"   # Rocky's cloud-init default user; "ubuntu" no longer exists
```

Verify the image is published in your project before applying:
```bash
gcloud compute images list \
  --project rocky-linux-cloud \
  --filter="family~rocky-linux-(8|9)$" \
  --format="table(name,family,status)"
```

You can pin to a specific build by passing the full image name instead of the
family alias, e.g. `gcp_image = "rocky-linux-cloud/rocky-linux-9-v20260415"`.

Heads-up for the downstream Ansible run:
- SELinux is **enforcing** by default on Rocky. Roles that touch system
  paths (Postgres data dir, etcd, custom systemd units) need correct file
  contexts or a deliberate policy adjustment.
- Use `ansible.builtin.package` / `dnf` — `apt` modules will fail.
- `/usr/bin/python3` is already present on Rocky 8 (3.6) and 9 (3.9), so the
  `ansible_python_interpreter` line in the generated inventory still works.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Attempted to load application default credentials … No credentials loaded` | ADC file missing | Run `gcloud auth application-default login` |
| `compute.instances.create … permission denied` | SA lacks roles | Grant `roles/compute.admin` on the project |
| `Quota 'CPUS' exceeded` | Region quota too small for `instance_type` | Request a quota bump or pick a smaller SKU |
| `Required 'compute.zones.get' permission` | Wrong project set | `gcloud config set project <id>` |
| Slow plan, hangs on `Refreshing state` | Network egress blocked | Check corporate proxy / `HTTPS_PROXY` env vars |
