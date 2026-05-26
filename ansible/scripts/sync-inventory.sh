#!/usr/bin/env bash
# sync-inventory.sh — copy Terraform-emitted Ansible artifacts into ansible/inventory/<cloud>/.
#
# Usage:   sync-inventory.sh <gcp|aws|azure>
#
# Idempotent: re-running overwrites the three synced files (hosts.yml, hosts.ini,
# credentials.json) but never touches group_vars/ or host_vars/.

set -euo pipefail

cloud="${1:-}"
case "$cloud" in
  gcp|aws|azure) ;;
  *)
    echo "usage: $(basename "$0") <gcp|aws|azure>" >&2
    exit 2
    ;;
esac

# Resolve the repo root from the script's own location, so users can invoke from anywhere.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

tf_dir="$repo_root/terraform/clouds/$cloud"
ansible_inv="$repo_root/ansible/inventory/$cloud"

for f in ansible_inventory.yml ansible_inventory.ini credentials.json; do
  if [[ ! -f "$tf_dir/$f" ]]; then
    echo "error: missing $tf_dir/$f" >&2
    echo "       Has 'terraform apply' run inside terraform/clouds/$cloud/?" >&2
    exit 1
  fi
done

mkdir -p "$ansible_inv/group_vars/all"

install -m 0644 "$tf_dir/ansible_inventory.yml" "$ansible_inv/hosts.yml"
install -m 0644 "$tf_dir/ansible_inventory.ini" "$ansible_inv/hosts.ini"
install -m 0600 "$tf_dir/credentials.json"      "$ansible_inv/credentials.json"

echo "Synced terraform/clouds/$cloud/ -> ansible/inventory/$cloud/"
for f in hosts.yml hosts.ini credentials.json; do
  printf '  %s\n' "$ansible_inv/$f"
done
