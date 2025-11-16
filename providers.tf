provider "vault" {
  address = var.vault_address
  token   = var.vault_admin_token
  namespace = "admin"
}
