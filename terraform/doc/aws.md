# Amazon Web Services (AWS) Setup

Use this guide when running `terraform` from `clouds/aws/`.

The Terraform module uses `aws_instance` + `aws_ebs_volume` +
`aws_volume_attachment`, plus a small security group and key pair. It
authenticates through the standard AWS credential chain (env vars →
`~/.aws/credentials` → IAM role on the host), so anything the `aws` CLI can
use, Terraform can use.

---

## 1. Install the `aws` CLI v2

### Linux (x86_64)
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws
```

### Linux (ARM64)
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install && rm -rf awscliv2.zip aws
```

### macOS
```bash
brew install awscli
# or: curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o AWSCLIV2.pkg
#     sudo installer -pkg AWSCLIV2.pkg -target /
```

### Verify the install
```bash
aws --version
# Should print: aws-cli/2.x.x Python/3.x.x …
```

---

## 2. Log in

Pick **one** of the following.

### Option A — Static IAM access key (simplest)
Create an IAM user with the policy `AmazonEC2FullAccess` (or a tighter custom
policy), then generate an access key:

```bash
aws configure
# AWS Access Key ID [None]: AKIA…
# AWS Secret Access Key [None]: …
# Default region name [None]: us-east-1
# Default output format [None]: json
```

That writes `~/.aws/credentials` and `~/.aws/config`. Terraform reads both.

### Option B — AWS IAM Identity Center (SSO) — recommended for human users
```bash
aws configure sso
# SSO start URL: https://your-org.awsapps.com/start
# SSO Region: us-east-1
# Follows browser flow, then asks you to name a profile
```

Then for every shell session:
```bash
export AWS_PROFILE=your-sso-profile-name
aws sso login --profile "$AWS_PROFILE"
```

### Option C — Environment variables (best for CI)
```bash
export AWS_ACCESS_KEY_ID=AKIA…
export AWS_SECRET_ACCESS_KEY=…
export AWS_SESSION_TOKEN=…       # only if using STS / assume-role
export AWS_DEFAULT_REGION=us-east-1
```

### Option D — IAM role on the host (best for EC2 / ECS / EKS)
Don't run `aws configure` at all. Attach an instance profile / task role with
the required EC2 permissions; the credential chain picks it up automatically.

---

## 3. Verify connectivity

Run these from the shell you'll run Terraform in:

```bash
# 3.1  CLI sees a valid identity
aws sts get-caller-identity
# {"UserId": "AIDA…", "Account": "1234…", "Arn": "arn:aws:iam::…"}

# 3.2  Region is set
aws configure get region
# us-east-1

# 3.3  EC2 API is reachable and you can list instance types
aws ec2 describe-instance-types --instance-types t3.micro --region us-east-1 \
  --query 'InstanceTypes[0].InstanceType' --output text
# t3.micro

# 3.4  You can list AMIs (Terraform will look one up if aws_ami is empty)
aws ec2 describe-images --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'Images[0].ImageId' --output text

# 3.5  Default VPC exists (the module falls back to it when aws_vpc_id is empty)
aws ec2 describe-vpcs --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' --output text
```

3.1 is the most important — if that returns an `Arn`, Terraform will work.

---

## 4. Wire it into the Terraform project

In `clouds/aws/terraform.tfvars`:
```hcl
aws_region = "us-east-1"

# Optional. Leave empty to let the module pick sensible defaults.
# aws_ami       = "ami-0abcdef…"   # default: latest Ubuntu 22.04 LTS
# aws_vpc_id    = "vpc-…"          # default: account's default VPC
# aws_subnet_id = "subnet-…"       # default: first subnet in resolved VPC
```

If you used **Option B (SSO)**:
```bash
export AWS_PROFILE=your-sso-profile-name
aws sso login --profile "$AWS_PROFILE"   # refresh expired SSO tokens
```

If you used **Option C (env vars)**: just make sure they're exported in the
same shell as `terraform apply`.

Then:
```bash
cd clouds/aws
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## 5. Switching to Rocky Linux 8 / 9

The AWS module's built-in AMI auto-lookup targets Ubuntu 22.04. To boot Rocky
Linux instead, look up a Rocky AMI in your region and pin it via tfvars — no
source changes required.

Rocky AMIs are published by the **Rocky Enterprise Software Foundation**
(AWS account `792107900819`).

```bash
# Latest Rocky Linux 9 AMI in your default region (swap "9" for "8" as needed)
aws ec2 describe-images \
  --owners 792107900819 \
  --filters "Name=name,Values=Rocky-9-EC2-Base-9.*-x86_64*" \
            "Name=architecture,Values=x86_64" \
            "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].[ImageId,Name]' \
  --output text
# ami-0abc…  Rocky-9-EC2-Base-9.4-20240509.0.x86_64
```

Then in `clouds/aws/terraform.tfvars`:
```hcl
aws_ami  = "ami-0abc…"   # the AMI ID printed above
ssh_user = "rocky"        # Rocky's cloud-init default user
```

> Rocky AMIs are region-scoped. If you change `aws_region`, re-run the
> `describe-images` query in that region — the AMI ID will be different.
> Use `Rocky-8-EC2-Base-8.*` for Rocky 8.

Heads-up for the downstream Ansible run:
- SELinux is **enforcing** by default on Rocky. Roles that touch system
  paths (Postgres data dir, etcd, custom systemd units) need correct file
  contexts or a deliberate policy adjustment.
- Use `ansible.builtin.package` / `dnf` — `apt` modules will fail.
- On Nitro instances the inventory's `data_disk_device`
  (`/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_*`) works the same on
  Rocky as on Ubuntu. On older Xen instances (t2/m4/etc.) you'll still need
  to override to `/dev/xvdf` via `host_vars/`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `InvalidClientTokenId: The security token … is invalid` | Wrong / expired access key | Regenerate via IAM, or `aws sso login` |
| `ExpiredToken` | Temporary credentials expired (typical with SSO/STS) | `aws sso login --profile <name>` |
| `UnauthorizedOperation` on `RunInstances` | IAM user/role lacks EC2 permissions | Attach `AmazonEC2FullAccess` (or a scoped policy) |
| `Could not connect to the endpoint URL` | Region misconfigured or air-gapped | Check `aws configure get region` and `HTTPS_PROXY` |
| `VPC … not found` | Custom `aws_vpc_id` set but VPC is in another region | Match `aws_region` to the VPC's region |
| `No default VPC found` | Default VPC was deleted | Set `aws_vpc_id` and `aws_subnet_id` explicitly in tfvars |
| Plan succeeds, apply fails on `aws_volume_attachment` with timeout | Disk in a different AZ than instance | Don't override AZ; the module derives it from the instance |

