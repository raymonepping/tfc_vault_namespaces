locals {
  # All attendee IDs from attendees.auto.tfvars.json
  attendee_ids = keys(var.attendees)

  # Namespace name per attendee, using namespace_suffix:
  #  - "raymon-e" -> "team_raymon-e"
  #  - "raymon-b" -> "team_raymon-b"
  #  - "jorg"     -> "team_jorg"
  attendee_namespace_names = {
    for id, attendee in var.attendees :
    id => "team_${attendee.namespace_suffix}"
  }
}

# 1) One namespace per attendee (top-level under admin)
#    Example in Vault UI:
#      - admin/team_jorg
#      - admin/team_raymon-e
#      - admin/team_raymon-b
resource "vault_namespace" "attendee" {
  for_each = var.attendees

  path = local.attendee_namespace_names[each.key]
}

# 2) Enable KV v2 at "secret/" inside each attendee namespace
resource "vault_mount" "attendee_kv" {
  for_each = var.attendees

  path      = "secret"
  type      = "kv-v2"

  # Namespace: e.g. "team_jorg", "team_raymon-e"
  namespace = vault_namespace.attendee[each.key].path
}

# 3) Per-attendee policy with full access to secret/*
resource "vault_policy" "attendee" {
  for_each = var.attendees

  name      = "workshop-${each.key}"
  # Namespace: e.g. "team_jorg", "team_raymon-e"
  namespace = vault_namespace.attendee[each.key].path

  policy = <<EOT
# Attendee: ${each.value.first_name} ${each.value.last_name} <${each.value.email}>
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOT
}

# 4) Enable userpass auth method in each namespace (at "userpass/")
resource "vault_auth_backend" "userpass" {
  for_each = var.attendees

  type      = "userpass"
  path      = "userpass"
  namespace = vault_namespace.attendee[each.key].path
}

# 5) Create one userpass user per attendee
#    Username: lower(first_name)
#    Password: VaultWorkshop-<first_name_lower>!
#
# This *still* works with duplicates because namespaces differ:
#   - admin/team_raymon-e : username "raymon"
#   - admin/team_raymon-b : username "raymon"
resource "vault_generic_endpoint" "userpass_user" {
  for_each = var.attendees

  namespace = vault_namespace.attendee[each.key].path
  path      = "auth/userpass/users/${lower(each.value.first_name)}"

  data_json = jsonencode({
    password = "VaultWorkshop-${lower(each.value.first_name)}!"
    policies = ["workshop-${each.key}"]
  })

  depends_on = [
    vault_auth_backend.userpass
  ]
}

# 6) Per-attendee story secret in KV v2
#    Path: secret/story
#    Fields: quote + attendee information
resource "vault_kv_secret_v2" "story" {
  for_each = var.attendees

  # KV v2 mount created earlier
  mount     = vault_mount.attendee_kv[each.key].path  # "secret"
  name      = "story"
  namespace = vault_namespace.attendee[each.key].path # e.g. "team_raymon-e"

  data_json = jsonencode({
    quote    = "The Story Has Been Yours All Along. You Just Didn't Know It."
    attendee = "${each.value.first_name} ${each.value.last_name}"
    email    = each.value.email
  })
}
