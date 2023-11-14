export STAGE_DIR=terraform/staging

terraform -chdir="$STAGE_DIR" destroy -auto-approve