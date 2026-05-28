# Microsoft Azure Setup

Use this guide when running `terraform` from `clouds/azure/`.

The Terraform module uses `azurerm_linux_virtual_machine` +
`azurerm_managed_disk`, plus a resource group, VNet, subnet, NSG, and public
IPs. It authenticates through the standard Azure CLI / Service Principal /
Managed Identity chain.

Because each cloud now lives in its own Terraform root, you **only** need
Azure credentials when working inside `clouds/azure/`. GCP and AWS roots
never touch Azure.

---

## 1. Install the `az` CLI

### Linux (Debian / Ubuntu)
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### Linux (RHEL / CentOS / Fedora)
```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
sudo dnf install -y azure-cli
```

### macOS
```bash
brew install azure-cli
```

### Universal installer
```bash
curl -L https://aka.ms/InstallAzureCli | bash
exec -l $SHELL
```

### Verify the install
```bash
az --version
# azure-cli                         2.xx.x
# core                              2.xx.x
# ...
```

---

## 2. Log in

Pick **one**.

### Option A — Interactive user login (best for laptops / dev)
```bash
az login                                  # browser opens
az account list --output table            # list subscriptions you can see
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
```

After this, the Terraform `azurerm` provider auto-detects your CLI session.
No env vars needed.

### Option B — Service Principal with secret (best for CI)
1. Create the SP (one-time, from an already-logged-in shell):
   ```bash
   az ad sp create-for-rbac \
     --name "poaf-terraform" \
     --role "Contributor" \
     --scopes "/subscriptions/<SUBSCRIPTION_ID>"
   ```
   Output looks like:
   ```json
   {
     "appId": "11111111-1111-1111-1111-111111111111",
     "displayName": "poaf-terraform",
     "password": "this-is-the-only-time-this-is-shown",
     "tenant": "22222222-2222-2222-2222-222222222222"
   }
   ```
2. Export those values **and** the subscription as standard `ARM_*` vars:
   ```bash
   export ARM_CLIENT_ID="<appId>"
   export ARM_CLIENT_SECRET="<password>"
   export ARM_TENANT_ID="<tenant>"
   export ARM_SUBSCRIPTION_ID="<subscription id>"
   ```

> ⚠️  Store the SP secret in a vault. Rotate it on schedule. **Never commit it.**

### Option C — Managed Identity (best for VMs / Azure DevOps agents)
On an Azure VM with a system-assigned managed identity:
```bash
export ARM_USE_MSI=true
export ARM_SUBSCRIPTION_ID="<subscription id>"
# Terraform / az will pick up the identity from IMDS automatically.
```

---

## 3. Verify connectivity

```bash
# 3.1  CLI sees a valid identity
az account show
# Should print the active subscription + tenant + user/SP.

# 3.2  You can resolve resource providers (proves the management API works)
az provider show --namespace Microsoft.Compute --query registrationState
# "Registered"

# 3.3  Your default location supports the VM SKUs you plan to use
az vm list-sizes --location "eastus" --query "[?name=='Standard_D4s_v5']"

# 3.4  You can create a resource group (and then clean it up)
az group create --name poaf-smoketest --location eastus
az group delete --name poaf-smoketest --yes --no-wait

# 3.5  Pure token check (matches what the Terraform provider does at configure time)
az account get-access-token --output none && echo "Token OK"
```

If 3.5 succeeds, the AzureRM Terraform provider will configure cleanly.

---

## 4. Wire it into the Terraform project

In `clouds/azure/terraform.tfvars`:
```hcl
azure_location       = "East US"
azure_resource_group = "poaf-rg"                # created if absent
# azure_image         = "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest"
```

In your shell, depending on which login option you used:

| Option | What to do per shell session |
|--------|------------------------------|
| A (`az login`) | Nothing — CLI session is cached in `~/.azure/` |
| B (SP secret)  | `export ARM_CLIENT_ID/_SECRET/_TENANT_ID/_SUBSCRIPTION_ID` |
| C (MSI)        | `export ARM_USE_MSI=true ARM_SUBSCRIPTION_ID=…` |

Then:
```bash
cd clouds/azure
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## 5. Switching to Rocky Linux 8 / 9

Rocky Linux images on Azure are published in the Marketplace by the
**Rocky Enterprise Software Foundation** under publisher `resf`. Switching is
a tfvars-only override — no source changes required — but Marketplace images
need a one-time license acceptance per subscription.

### 5.1 Accept the Marketplace terms (one-time, per subscription)
```bash
# Rocky Linux 9
az vm image terms accept --urn resf:rockylinux-x86_64:9-base:latest

# …or Rocky Linux 8
az vm image terms accept --urn resf:rockylinux-x86_64:8-base:latest
```
Without this, `terraform apply` fails with
`PurchasePlanNotAccepted` / `MarketplacePurchaseEligibilityFailed` when the
VM resource is created.

### 5.2 Confirm the image is available in your location
```bash
az vm image list \
  --publisher resf \
  --offer rockylinux-x86_64 \
  --location "$(az vm image list --publisher resf --query '[0].location' -o tsv 2>/dev/null || echo eastus)" \
  --all --output table
```

### 5.3 Set the tfvars overrides
In `clouds/azure/terraform.tfvars`:
```hcl
azure_image = "resf:rockylinux-x86_64:9-base:latest"   # or 8-base:latest
ssh_user    = "rocky"                                  # Rocky's default user

# Marketplace images additionally need a `plan` block matching the
# accepted terms — without it, VM creation fails with VMMarketplaceInvalidInput
# even though `az vm image terms accept` succeeded.
azure_image_plan = {
  publisher = "resf"
  product   = "rockylinux-x86_64"
  name      = "9-base"   # must match the SKU in azure_image
}
```

The `azure_image` string is `publisher:offer:sku:version`, split by the module
and fed straight to `source_image_reference`. To pin a specific build, replace
`latest` with the version tag returned by step 5.2.

`azure_image_plan` defaults to `null`, which is correct for images that don't
require Marketplace terms (Ubuntu, RHEL pay-as-you-go via the `RedHat`
publisher, etc.). It's only needed when you also had to run
`az vm image terms accept`.

Heads-up for the downstream Ansible run:
- SELinux is **enforcing** by default on Rocky. Roles that touch system
  paths (Postgres data dir, etcd, custom systemd units) need correct file
  contexts or a deliberate policy adjustment.
- Use `ansible.builtin.package` / `dnf` — `apt` modules will fail.
- The inventory's `data_disk_device=/dev/disk/azure/scsi1/lun10` works
  identically on Rocky and Ubuntu — the LUN path is provided by the Azure
  hypervisor, not the guest distro.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `executable file not found in $PATH: az` | Azure CLI not installed | Install `az` (section 1) |
| `AADSTS700038: … is not a valid application identifier` | `ARM_CLIENT_ID` is wrong | Set the right SP `appId`, or use `az login` instead |
| `AuthorizationFailed: …does not have authorization to perform action 'Microsoft.Compute/…'` | SP role too narrow | Grant `Contributor` on the subscription or RG |
| `SubscriptionNotFound` | Wrong `ARM_SUBSCRIPTION_ID` | `az account list` and copy the correct one |
| `LocationNotAvailableForResourceType` | SKU not offered in `azure_location` | Pick a different region or VM size |
| `VMMarketplaceInvalidInput: …requires Plan information…` | Marketplace image (Rocky, Alma, …) without `azure_image_plan` | Set `azure_image_plan` to match the accepted URN — see §5.3 |
| `PurchasePlanNotAccepted` / `MarketplacePurchaseEligibilityFailed` | Marketplace terms not accepted on this subscription | `az vm image terms accept --urn <publisher>:<offer>:<sku>:latest` — see §5.1 |
| `OperationNotAllowed: Quota exceeded` | Sub-level vCPU quota | Open a quota-increase request in the portal |
| Slow plan, hangs talking to `login.microsoftonline.com` | Corporate proxy | Set `HTTPS_PROXY` env var consistently for both `az` and `terraform` |
