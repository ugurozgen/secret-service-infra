#!/bin/bash

export AWS_PROFILE=default
export PROJECT_NAME=secret-service-infra
export S3_BUCKET=secret-service-infra
export AWS_REGION=eu-north-1
export STAGE_DIR=terraform/staging
export GIT_REPO=git@github.com:ugurozgen/secret-service-infra.git
export NAMESPACE=secret-service

export TF_VAR_project_name=$PROJECT_NAME
export TF_VAR_region=$AWS_REGION

createS3Bucket(){
    # create s3 bucket
    aws s3 mb s3://$PROJECT_NAME --region $AWS_REGION > /dev/null 2>&1
    # enable bucket versioning
    aws s3api put-bucket-versioning \
        --bucket $PROJECT_NAME \
        --versioning-configuration Status=Enabled \
        --region $AWS_REGION
}

deployStageEKS(){
    terraform -chdir="$STAGE_DIR" init \
        -input=false \
        -backend=true \
        -backend-config="bucket=$S3_BUCKET" \
        -backend-config="key=staging/terraform.tfstate" \
        -backend-config="region=$AWS_REGION" \
        -reconfigure
    # terraform validate the staging env
    terraform -chdir="$STAGE_DIR" fmt -recursive
    terraform -chdir="$STAGE_DIR" validate
    # terraform plan + apply the staging env
    terraform -chdir="$STAGE_DIR" plan -out=terraform.plan
    terraform -chdir="$STAGE_DIR" apply -auto-approve terraform.plan
}

deployArgoCD(){
    helm repo add argo-cd https://argoproj.github.io/argo-helm
    helm dep update charts/argo-cd/

    helm install argo-cd charts/argo-cd/ --namespace argocd

    kubectl wait deploy argocd-server \
        --timeout=180s \
        --namespace argocd \
        --for=condition=Available=True
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
    # wait until argocd updated
    while true; do
        ARGO_LOAD_BALANCER=$(kubectl get svc argocd-server \
            --namespace argocd \
            --output json |
            jq --raw-output '.status.loadBalancer.ingress[0].hostname')
        [[ "$ARGO_LOAD_BALANCER" != 'null' ]] && break;
    done
    echo ARGO_LOAD_BALANCER $ARGO_LOAD_BALANCER

    # wait until argocd available via loadbalancer
    while [[ -z $(curl $ARGO_LOAD_BALANCER 2>/dev/null) ]]; do sleep 1; done

    ARGO_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
        --namespace argocd \
        --output jsonpath="{.data.password}" |
        base64 --decode)
    echo ARGO_PASSWORD $ARGO_PASSWORD

    argocd login $ARGO_LOAD_BALANCER \
        --insecure \
        --username=admin \
        --password=$ARGO_PASSWORD

    helm template charts/root-app/ | kubectl apply -f -
}

addRepoToArgoCD(){
    if [[ ! -f ~/.ssh/$PROJECT_NAME.pem ]];
    then
        ssh-keygen -t ed25519 -N "" -f ~/.ssh/$PROJECT_NAME.pem
        mv ~/.ssh/$PROJECT_NAME.pem.pub ~/.ssh/$PROJECT_NAME.pub
    fi

    if [[ -z $(gh ssh-key list | grep ^$PROJECT_NAME) ]];
    then
        gh ssh-key add ~/.ssh/$PROJECT_NAME.pub --title $PROJECT_NAME
    fi

    argocd repo add $GIT_REPO \
        --insecure-ignore-host-key \
        --ssh-private-key-path ~/.ssh/$PROJECT_NAME.pem
}

deploySecretService(){
    # create secret-service application on Argo CD
    export NAMESPACE=staging
    export SERVER=https://kubernetes.default.svc
    cat argocd/argocd-app.yaml | envsubst | kubectl apply -f -

    while [[ -z $(kubectl get ns secret-service 2>/dev/null) ]]; do sleep 1; done

    while true; do
        SECRET_SERVICE_LOAD_BALANCER=$(kubectl get svc secret-service \
            --namespace secret-service \
            --output json |
            jq --raw-output '.status.loadBalancer.ingress[0].hostname')
        [[ "$SECRET_SERVICE_LOAD_BALANCER" != 'null' ]] && break;
    done
    echo SECRET_SERVICE_LOAD_BALANCER $SECRET_SERVICE_LOAD_BALANCER
}

# createS3Bucket
# deployStageEKS

# #### KUBECTL for STAGING ####
# aws eks update-kubeconfig --name ${PROJECT_NAME}-staging --region $AWS_REGION

deployArgoCD
addRepoToArgoCD
deploySecretService

