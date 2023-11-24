output "project_name" {
  value = var.project_name
}

output "project_env" {
  value = var.project_env
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_private_subnets" {
  value = module.vpc.private_subnets
}

output "eks_cluster_id" {
  value = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "vault_init_key_id_stg" {
  value = module.eks.vault_init_key_id_stg
}

output "vault_init_key_id_prod" {
  value = module.eks.vault_init_key_id_prod
}
