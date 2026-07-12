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
  }
}
