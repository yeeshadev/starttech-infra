#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"
ACTION="${1:-plan}"

# ── Dependency checks ─────────────────────────────────────────────────────────
info "Checking dependencies..."
command -v terraform >/dev/null 2>&1 || error "terraform is not installed"
command -v aws >/dev/null 2>&1       || error "aws CLI is not installed"

TERRAFORM_VERSION=$(terraform version -json | grep '"terraform_version"' | cut -d'"' -f4)
info "Terraform version: ${TERRAFORM_VERSION}"

AWS_IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null) || error "AWS credentials not configured"
AWS_ACCOUNT=$(echo "$AWS_IDENTITY" | grep '"Account"' | cut -d'"' -f4)
success "Authenticated as account: ${AWS_ACCOUNT}"

# ── Required env vars ─────────────────────────────────────────────────────────
: "${TF_VAR_mongo_uri:?TF_VAR_mongo_uri must be set}"
: "${TF_VAR_jwt_secret_key:?TF_VAR_jwt_secret_key must be set}"

# ── Init ──────────────────────────────────────────────────────────────────────
info "Initialising Terraform in ${TF_DIR}..."
cd "$TF_DIR"
terraform init -upgrade

# ── Validate ──────────────────────────────────────────────────────────────────
info "Validating configuration..."
terraform validate
terraform fmt -check -recursive && success "Formatting OK" || warn "Some files need formatting (run: terraform fmt -recursive)"

# ── Plan ──────────────────────────────────────────────────────────────────────
info "Running Terraform plan..."
terraform plan -out=tfplan -no-color | tee plan_output.txt
success "Plan saved to ${TF_DIR}/tfplan"

if [[ "$ACTION" == "plan" ]]; then
  info "Dry-run complete. To apply, run: $0 apply"
  exit 0
fi

# ── Apply ─────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "apply" ]]; then
  echo ""
  warn "You are about to apply the above plan to AWS account ${AWS_ACCOUNT}."
  read -r -p "Type 'yes' to confirm: " CONFIRM
  [[ "$CONFIRM" == "yes" ]] || { info "Aborted."; exit 0; }

  info "Applying infrastructure changes..."
  terraform apply tfplan

  info "Saving outputs..."
  terraform output -json > "${SCRIPT_DIR}/../outputs.json"
  success "Outputs saved to outputs.json"

  echo ""
  echo -e "${GREEN}════ Deployment complete ════${NC}"
  terraform output
fi

# ── Destroy ───────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "destroy" ]]; then
  warn "DESTRUCTIVE: This will DESTROY all infrastructure in account ${AWS_ACCOUNT}!"
  read -r -p "Type 'destroy' to confirm: " CONFIRM
  [[ "$CONFIRM" == "destroy" ]] || { info "Aborted."; exit 0; }

  terraform destroy -auto-approve
  success "Infrastructure destroyed."
fi
