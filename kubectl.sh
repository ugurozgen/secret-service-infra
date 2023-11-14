#!/bin/bash

export AWS_PROFILE=default
export PROJECT_NAME=secret-service-infra
export AWS_REGION=eu-north-1
export TF_VAR_project_name=$PROJECT_NAME
export TF_VAR_region=$AWS_REGION
export STAGE_DIR=terraform/staging

OUTPUT=$(terraform -chdir="$STAGE_DIR" output --json)
NAME=$(echo "$OUTPUT" | jq --raw-output '.eks_cluster_id.value')
log NAME $NAME
REGION=$(echo "$OUTPUT" | jq --raw-output '.region.value')
log REGION $REGION