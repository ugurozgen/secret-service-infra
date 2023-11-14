PROJECT_NAME = secret-service-infra
S3_BUCKET = secret-service-infra
AWS_REGION = eu-north-1
STAGE_DIR = terraform/staging

init: # setup project + create S3 bucket
# create s3 bucket
	aws s3 mb s3://$(PROJECT_NAME) --region $(AWS_REGION) > /dev/null 2>&1
# enable bucket versioning
	aws s3api put-bucket-versioning \
		--bucket $(PROJECT_NAME) \
		--versioning-configuration Status=Enabled \
		--region $(AWS_REGION)

staging-init: # terraform init the staging env
	terraform -chdir="$(STAGE_DIR)" init \
		-input=false \
		-backend=true \
		-backend-config="bucket=$(S3_BUCKET)" \
		-backend-config="key=staging/terraform.tfstate" \
		-backend-config="region=$(AWS_REGION)" \
		-reconfigure

staging-validate: # terraform validate the staging env
	terraform -chdir="$(STAGE_DIR)" fmt -recursive
	terraform -chdir="$(STAGE_DIR)" validate

staging-apply: # terraform plan + apply the staging env
	terraform -chdir="$(STAGE_DIR)" plan -out=terraform.plan
	terraform -chdir="$(STAGE_DIR)" apply -auto-approve terraform.plan

staging-destroy: # terraform destroy the staging env
	terraform -chdir="$(STAGE_DIR)" destroy -auto-approve

staging-kubectl:
	aws eks update-kubeconfig --name $(PROJECT_NAME)-staging --region $(AWS_REGION)
	kubectl get configmap aws-auth \
        --namespace kube-system \
        --output yaml > "aws-auth-configmap.yaml"

install-argocd:
	kubectl create namespace argocd
	kubectl apply \
        --namespace argocd \
        --filename https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl wait deploy argocd-server \
        --timeout=180s \
        --namespace argocd \
        --for=condition=Available=True
	kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
	

production-init: # terraform init the production env
	./make.sh production-init

production-validate: # terraform validate the production env
	./make.sh production-validate

production-apply: # terraform plan + apply the production env
	./make.sh production-apply

production-destroy: # terraform destroy the production env
	./make.sh production-destroy

eks-staging-config: # setup kubectl config + aws-auth configmap for staging env
	./make.sh eks-staging-config

eks-production-config: # setup kubectl config + aws-auth configmap for production env
	./make.sh eks-production-config

argo-install: # install argocd in staging env
	./make.sh argo-install

argo-login: # argocd cli login + show access data
	./make.sh argo-login

argo-add-repo: # add git repo connection + create ssh key + add ssh key to github
	./make.sh argo-add-repo

argo-add-cluster: # argocd add production cluster
	./make.sh argo-add-cluster

argo-staging-app: # create argocd staging app
	./make.sh argo-staging-app

argo-production-app: # create argocd production app
	./make.sh argo-production-app

argo-destroy: # delete argocd apps then argocd
	./make.sh argo-destroy