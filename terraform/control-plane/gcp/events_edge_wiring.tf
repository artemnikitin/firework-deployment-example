# -----------------------------------------------------------------------------
# Durable Events edge wiring
# -----------------------------------------------------------------------------

data "terraform_remote_state" "events_edge" {
  count = var.use_events_edge_remote_state && fileexists(local.events_edge_state_path_resolved) ? 1 : 0

  backend = "local"
  config = {
    path = local.events_edge_state_path_resolved
  }
}

locals {
  events_edge_state_path_expanded = pathexpand(var.events_edge_state_path)
  events_edge_state_path_resolved = startswith(local.events_edge_state_path_expanded, "/") ? local.events_edge_state_path_expanded : abspath("${path.module}/${local.events_edge_state_path_expanded}")

  events_edge_state_found = var.use_events_edge_remote_state && fileexists(local.events_edge_state_path_resolved)
  events_edge_outputs     = local.events_edge_state_found ? try(data.terraform_remote_state.events_edge[0].outputs, {}) : {}

  effective_events_gateway_address_name = var.events_gateway_address_name != "" ? var.events_gateway_address_name : try(local.events_edge_outputs.events_gateway_address_name, "")
  effective_events_certificate_map_name = var.events_certificate_map_name != "" ? var.events_certificate_map_name : try(local.events_edge_outputs.events_certificate_map_name, "")
  events_edge_domain                    = try(local.events_edge_outputs.events_domain, "")
  status_edge_domain                    = try(local.events_edge_outputs.status_domain, "")
  effective_status_domain               = var.status_domain != "" ? trimsuffix(var.status_domain, ".") : local.status_edge_domain
}

resource "terraform_data" "validate_events_edge_wiring" {
  lifecycle {
    precondition {
      condition = (
        local.events_edge_state_found ||
        (var.events_gateway_address_name != "" && var.events_certificate_map_name != "")
      )
      error_message = format("Events edge state file not found at %s (from events_edge_state_path=%s). Apply terraform/events-edge/gcp first, set events_edge_state_path correctly, or provide events_gateway_address_name and events_certificate_map_name manually.", local.events_edge_state_path_resolved, var.events_edge_state_path)
    }

    precondition {
      condition     = local.effective_events_gateway_address_name != ""
      error_message = "events_gateway_address_name is required (set explicitly or auto-wire from the Events edge state)."
    }

    precondition {
      condition     = local.effective_events_certificate_map_name != ""
      error_message = "events_certificate_map_name is required (set explicitly or auto-wire from the Events edge state)."
    }

    precondition {
      condition     = !local.events_edge_state_found || local.events_edge_domain == trimsuffix(var.events_domain, ".")
      error_message = "events_domain must match the durable Events edge state. Apply the matching edge stack or correct events_domain."
    }

    precondition {
      condition     = local.effective_status_domain != ""
      error_message = "status_domain is required (set explicitly or auto-wire it from an updated durable Events edge state)."
    }

    precondition {
      condition     = trimsuffix(var.events_domain, ".") != local.effective_status_domain
      error_message = "events_domain and status_domain must be different hostnames."
    }

    precondition {
      condition     = !local.events_edge_state_found || var.status_domain == "" || local.status_edge_domain == trimsuffix(var.status_domain, ".")
      error_message = "status_domain must match the durable Events edge state. Apply the matching edge stack or correct status_domain."
    }
  }
}
