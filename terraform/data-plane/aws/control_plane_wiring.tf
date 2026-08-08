data "terraform_remote_state" "control_plane" {
  count = fileexists(local.control_plane_state_path_resolved) ? 1 : 0

  backend = "local"
  config = {
    path = local.control_plane_state_path_resolved
  }
}

locals {
  control_plane_state_path_expanded = pathexpand(var.control_plane_state_path)
  control_plane_state_path_resolved = startswith(local.control_plane_state_path_expanded, "/") ? local.control_plane_state_path_expanded : abspath("${path.module}/${local.control_plane_state_path_expanded}")

  control_plane_state_found = fileexists(local.control_plane_state_path_resolved)
  control_plane_outputs     = local.control_plane_state_found ? try(data.terraform_remote_state.control_plane[0].outputs, {}) : {}

  effective_s3_configs_bucket_id  = try(local.control_plane_outputs.config_bucket_name, "")
  effective_s3_configs_bucket_arn = try(local.control_plane_outputs.config_bucket_arn, "")
  effective_s3_configs_prefix     = try(local.control_plane_outputs.config_prefix, "cp/v1/")

  effective_registry_url                        = try(local.control_plane_outputs.registry_url, "")
  effective_registry_server_name                = try(local.control_plane_outputs.registry_server_name, "")
  effective_registry_client_ca_secret_arn       = try(local.control_plane_outputs.registry_client_ca_secret_arn, "")
  effective_registry_bootstrap_token_secret_arn = try(local.control_plane_outputs.registry_bootstrap_token_secret_arn, "")
}

resource "terraform_data" "validate_control_plane_wiring" {
  lifecycle {
    precondition {
      condition     = local.control_plane_state_found
      error_message = format("control-plane state file not found at %s (from control_plane_state_path=%s). Apply control-plane first or set control_plane_state_path correctly.", local.control_plane_state_path_resolved, var.control_plane_state_path)
    }

    precondition {
      condition     = local.effective_s3_configs_bucket_id != "" && local.effective_s3_configs_bucket_arn != ""
      error_message = "Control-plane state must export config_bucket_name and config_bucket_arn."
    }

    precondition {
      condition     = local.effective_s3_configs_prefix == "" || endswith(local.effective_s3_configs_prefix, "/")
      error_message = "Control-plane config_prefix must end with '/'."
    }

    precondition {
      condition     = local.effective_registry_url != ""
      error_message = format("Control-plane state must export registry_url. Check control_plane_state_path=%s.", local.control_plane_state_path_resolved)
    }

    precondition {
      condition     = local.effective_registry_server_name != ""
      error_message = "Control-plane state must export registry_server_name for TLS validation."
    }

    precondition {
      condition     = local.effective_registry_client_ca_secret_arn != ""
      error_message = "Control-plane state must export registry_client_ca_secret_arn."
    }

    precondition {
      condition     = local.effective_registry_bootstrap_token_secret_arn != ""
      error_message = "Control-plane state must export registry_bootstrap_token_secret_arn."
    }
  }
}
