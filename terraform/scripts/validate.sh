#!/usr/bin/env bash
# Pre-apply validation wrapper. Intended for CI and local pre-commit use.
#
# Format-checks the whole repo, then runs init+validate inside each
# clouds/<X>/ root so per-cloud configs are independently verified.

set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> terraform fmt -check -recursive (repo-wide)"
terraform fmt -check -recursive

for cloud_dir in clouds/*/; do
  cloud_name="${cloud_dir%/}"
  echo "==> $cloud_name"
  terraform -chdir="$cloud_dir" init -backend=false -input=false >/dev/null
  terraform -chdir="$cloud_dir" validate
done

if command -v tflint >/dev/null 2>&1; then
  echo "==> tflint --recursive"
  tflint --recursive
else
  echo "==> tflint not installed; skipping"
fi

echo "OK: validation passed"
