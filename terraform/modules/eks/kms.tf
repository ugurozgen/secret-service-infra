resource "aws_kms_key" "vault_init_staging" {
  description             = "This key is used for vault init"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "vault_init_staging_alias" {
  name          = "alias/vault_init_staging"
  target_key_id = aws_kms_key.vault_init_staging.key_id
}

resource "aws_kms_key" "vault_init_production" {
  description             = "This key is used for vault init"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "vault_init_production_alias" {
  name          = "alias/vault_init_production"
  target_key_id = aws_kms_key.vault_init_production.key_id
}
