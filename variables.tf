variable "vault_address" {
  type        = string
  description = "HCP Vault URL (https://<cluster-id>.vault.hashicorp.cloud:8200)"
}

variable "vault_admin_token" {
  type        = string
  description = "Admin token for provisioning workshop namespaces"
  sensitive   = true
}

variable "attendees" {
  type = map(object({
    email            = string
    first_name       = string
    last_name        = string
    company          = string
    namespace_suffix = string
  }))
}
