output "cluster_id" {
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
}

output "vault_init_key_id_stg" {
  value       = join("",aws_kms_key.vault_init_staging.*.arn)
}

output "vault_init_key_id_prod" {
  value       = join("",aws_kms_key.vault_init_production.*.arn)
}