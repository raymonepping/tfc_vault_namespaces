output "attendee_namespaces" {
  value = {
    for id, attendee in var.attendees :
    id => {
      namespace_path = vault_namespace.attendee[id].path
      email          = attendee.email
      first_name     = attendee.first_name
      last_name      = attendee.last_name
      company        = attendee.company
    }
  }
}
