# -----------------------------------------------------------------------------
# Optional auto-wiring from control-plane Terraform outputs
# -----------------------------------------------------------------------------

data "terraform_remote_state" "control_plane" {
  count = var.use_control_plane_remote_state && fileexists(local.control_plane_state_path_resolved) ? 1 : 0

  backend = "local"
  config = {
    path = local.control_plane_state_path_resolved
  }
}

locals {
  control_plane_state_path_expanded = pathexpand(var.control_plane_state_path)
  control_plane_state_path_resolved = startswith(local.control_plane_state_path_expanded, "/") ? local.control_plane_state_path_expanded : abspath("${path.module}/${local.control_plane_state_path_expanded}")

  control_plane_state_found = var.use_control_plane_remote_state && fileexists(local.control_plane_state_path_resolved)
  control_plane_outputs     = local.control_plane_state_found ? try(data.terraform_remote_state.control_plane[0].outputs, {}) : {}

  effective_config_bucket_name = try(local.control_plane_outputs.config_bucket_name, "") != "" ? try(local.control_plane_outputs.config_bucket_name, "") : var.config_bucket_name
  effective_config_prefix      = try(local.control_plane_outputs.config_prefix, "") != "" ? try(local.control_plane_outputs.config_prefix, "") : (var.config_prefix != "" ? var.config_prefix : "cp/v1/")

  effective_registry_url         = var.registry_url != "" ? var.registry_url : try(local.control_plane_outputs.registry_url, "")
  effective_registry_server_name = var.registry_server_name != "" ? var.registry_server_name : try(local.control_plane_outputs.registry_server_name, "")

  effective_registry_ca_secret_id              = var.registry_ca_secret_id != "" ? var.registry_ca_secret_id : try(local.control_plane_outputs.registry_ca_secret_id, "")
  effective_registry_bootstrap_token_secret_id = var.registry_bootstrap_token_secret_id != "" ? var.registry_bootstrap_token_secret_id : try(local.control_plane_outputs.registry_bootstrap_token_secret_id, "")
  effective_control_plane_network_self_link    = var.control_plane_network_self_link != "" ? var.control_plane_network_self_link : try(local.control_plane_outputs.controlplane_network_self_link, "")
  effective_registry_allowed_cidrs             = try(local.control_plane_outputs.registry_allowed_cidrs, [])

  # True when some allowlist entry actually contains network_cidr, not merely
  # when one equals it: an allowlist of ["10.0.0.0/8"] covers a 10.30.0.0/24
  # data plane. An entry contains network_cidr when its prefix is no longer and
  # network_cidr's network address re-masked to that prefix matches the entry's.
  # try() keeps a malformed allowlist entry from the control-plane state
  # surfacing as an opaque cidrhost error instead of the precondition message.
  registry_allowlist_covers_network_cidr = try(anytrue([
    for cidr in local.effective_registry_allowed_cidrs :
    tonumber(split("/", cidr)[1]) <= tonumber(split("/", var.network_cidr)[1]) &&
    cidrhost(cidr, 0) == cidrhost("${cidrhost(var.network_cidr, 0)}/${split("/", cidr)[1]}", 0)
  ]), false)
}

resource "terraform_data" "validate_control_plane_wiring" {
  lifecycle {
    precondition {
      condition = (
        !var.use_control_plane_remote_state ||
        local.control_plane_state_found ||
        (var.config_bucket_name != "" && var.registry_url != "")
      )
      error_message = format("control-plane state file not found at %s (from control_plane_state_path=%s). Apply control-plane first, set control_plane_state_path correctly, or provide config_bucket_name and registry_url manually.", local.control_plane_state_path_resolved, var.control_plane_state_path)
    }

    precondition {
      condition     = local.effective_config_bucket_name != ""
      error_message = "config_bucket_name is required (set explicitly or auto-wire from control-plane outputs)."
    }

    precondition {
      condition     = local.effective_config_prefix == "" || endswith(local.effective_config_prefix, "/")
      error_message = "Resolved config_prefix must end with '/'."
    }

    precondition {
      condition     = local.effective_registry_url != ""
      error_message = format("registry_url is required for node enrollment/heartbeat (set explicitly or auto-wire from control-plane outputs). If auto-wiring is enabled, verify control_plane_state_path resolves to %s.", local.control_plane_state_path_resolved)
    }

    precondition {
      condition     = local.effective_registry_server_name != ""
      error_message = "registry_server_name could not be determined. Set registry_server_name explicitly or provide a valid registry_url via auto-wiring."
    }

    precondition {
      condition     = local.effective_registry_ca_secret_id != ""
      error_message = "registry_ca_secret_id is required. Set it explicitly or auto-wire from control-plane outputs."
    }

    precondition {
      condition     = local.effective_registry_bootstrap_token_secret_id != ""
      error_message = "registry_bootstrap_token_secret_id is required. Set it explicitly or auto-wire from control-plane outputs."
    }

    precondition {
      condition     = local.effective_control_plane_network_self_link != ""
      error_message = "control-plane network self-link is required for the private registry peering. Apply control-plane first or set control_plane_network_self_link explicitly."
    }

    precondition {
      condition = (
        length(local.effective_registry_allowed_cidrs) == 0 ||
        local.registry_allowlist_covers_network_cidr
      )
      error_message = format("The data-plane network_cidr %s is not covered by the control-plane registry_allowed_cidrs %s. Update the control-plane allowlist before moving or creating this data plane.", var.network_cidr, join(", ", local.effective_registry_allowed_cidrs))
    }
  }
}
