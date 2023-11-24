export STAGE_DIR=terraform/staging

terraform -chdir="$STAGE_DIR" destroy -auto-approve

export PROD_DIR=terraform/production

terraform -chdir="$PROD_DIR" destroy -auto-approve