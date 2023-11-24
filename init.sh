#!/bin/bash

export AWS_PROFILE=default
export PROJECT_NAME=secret-service-infra
export S3_BUCKET=secret-service-infra
export AWS_REGION=eu-north-1
export STAGE_DIR=terraform/staging
export PROD_DIR=terraform/production
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

deployEKSToStaging(){
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

deployVaultToStaging(){
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm install vault \
        --namespace vault --create-namespace \
        -f charts/vault/values.yaml \
        hashicorp/vault

    echo wait until Vault service updated to LoadBalancer
    while true; do
        VAULT_LOAD_BALANCER=$(kubectl get svc vault-ui \
            --namespace vault \
            --output json |
            jq --raw-output '.status.loadBalancer.ingress[0].hostname')
        [[ "$VAULT_LOAD_BALANCER" != 'null' ]] && break;
    done
    echo VAULT_LOAD_BALANCER $VAULT_LOAD_BALANCER

    echo wait until Vault available via LoadBalancer
    while [[ -z $(curl $VAULT_LOAD_BALANCER:8200/v1/sys/health 2>/dev/null) ]]; do sleep 1; done
    
    # unseal vault
    KMS_KEY_ID=$(terraform -chdir="$STAGE_DIR" output -raw vault_init_key_id_stg)
    docker run \
    -e CHECK_INTERVAL="10" \
    -e S3_BUCKET_NAME=$S3_BUCKET \
    -e KMS_KEY_ID=$KMS_KEY_ID \
    -e S3_PATH=staging/ \
    -e VAULT_ADDR=http://$VAULT_LOAD_BALANCER:8200 \
    -v ~/.aws:/home/newuser/.aws \
    ugurozgen/vault-init:0.0.7

    # download root token to login vault and enable kv-v2 engine
    aws s3 cp s3://$S3_BUCKET/staging/root-token.json.enc enc-root-token 
    VAULT_ROOT_TOKEN=$(aws kms decrypt \
        --ciphertext-blob fileb://enc-root-token \
        --key-id $KMS_KEY_ID \
        --output text \
        --query Plaintext | base64 \
        --decode )

    kubectl exec -it vault-0 -n vault -- vault login $VAULT_ROOT_TOKEN  > /dev/null
    kubectl exec -it vault-0 -n vault -- vault secrets enable kv-v2
}


deployArgoCDToStaging(){
    kubectl create namespace argocd
    kubectl apply \
        --namespace argocd \
        --filename https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
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

deploySecretServiceStage(){
    # create secret-service application on Argo CD
    export NAMESPACE=staging
    export SERVER=https://kubernetes.default.svc
    kubectl config use-context $PROJECT_NAME-staging
    cat argocd/argocd-app.yaml | envsubst | kubectl apply -f -

    while [[ -z $(kubectl get ns secret-service 2>/dev/null) ]]; do sleep 1; done

    echo wait for secret service is up on staging env
    while true; do
        SECRET_SERVICE_LOAD_BALANCER=$(kubectl get svc secret-service \
            --namespace secret-service \
            --output json |
            jq --raw-output '.status.loadBalancer.ingress[0].hostname')
        [[ "$SECRET_SERVICE_LOAD_BALANCER" != 'null' ]] && break;
    done
    echo STAGE_SECRET_SERVICE_LOAD_BALANCER $SECRET_SERVICE_LOAD_BALANCER

    while [[ -z $(curl $SECRET_SERVICE_LOAD_BALANCER 2>/dev/null) ]]; do sleep 1; done
    echo STAGING READY "http://$SECRET_SERVICE_LOAD_BALANCER" is available

}

deployProdEKS(){
    terraform -chdir="$PROD_DIR" init \
        -input=false \
        -backend=true \
        -backend-config="bucket=$S3_BUCKET" \
        -backend-config="key=production/terraform.tfstate" \
        -backend-config="region=$AWS_REGION" \
        -reconfigure
    # terraform validate the staging env
    terraform -chdir="$PROD_DIR" fmt -recursive
    terraform -chdir="$PROD_DIR" validate
    # terraform plan + apply the staging env
    terraform -chdir="$PROD_DIR" plan -out=terraform.plan
    terraform -chdir="$PROD_DIR" apply -auto-approve terraform.plan
}

deploySecretServiceProd(){
    # create secret-service application on Argo CD
    export NAMESPACE=production
    export SERVER=$(terraform -chdir="$PROD_DIR" output -raw eks_cluster_endpoint)
    kubectl config use-context $PROJECT_NAME-production
    cat argocd/argocd-app.yaml | envsubst | kubectl apply -f -

    while [[ -z $(kubectl get ns gitops-multienv 2>/dev/null) ]]; do sleep 1; done

    echo wait for secret service is up on prod env
    while true; do
        SECRET_SERVICE_LOAD_BALANCER=$(kubectl get svc secret-service \
            --namespace secret-service \
            --output json |
            jq --raw-output '.status.loadBalancer.ingress[0].hostname')
        [[ "$SECRET_SERVICE_LOAD_BALANCER" != 'null' ]] && break;
    done
    echo PROD_SECRET_SERVICE_LOAD_BALANCER $SECRET_SERVICE_LOAD_BALANCER

    while [[ -z $(curl $SECRET_SERVICE_LOAD_BALANCER 2>/dev/null) ]]; do sleep 1; done
    echo PROD READY "http://$SECRET_SERVICE_LOAD_BALANCER" is available

}

# createS3Bucket

# deployEKSToStaging

# #### KUBECTL for STAGING ####
# aws eks update-kubeconfig --name ${PROJECT_NAME}-staging --region $AWS_REGION

deployVaultToStaging
# deployArgoCDToStaging
# addRepoToArgoCD

# deploySecretServiceStage

# deployProdEKS

# #### KUBECTL for PROD ####
# aws eks update-kubeconfig --name ${PROJECT_NAME}-production --region $AWS_REGION

# argocd cluster add --yes ${PROJECT_NAME}-production

# deploySecretServiceProd
