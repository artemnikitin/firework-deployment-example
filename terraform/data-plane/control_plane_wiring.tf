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

  control_plane_config_bucket_name = try(local.control_plane_outputs.config_bucket_name, "")
  control_plane_config_bucket_arn  = try(local.control_plane_outputs.config_bucket_arn, "")
  control_plane_config_prefix      = try(local.control_plane_outputs.config_prefix, "")

  # When control-plane outputs are available, prefer them over potentially stale
  # manual tfvars values. Manual values remain a fallback when state is missing.
  effective_s3_configs_bucket_id  = local.control_plane_config_bucket_name != "" ? local.control_plane_config_bucket_name : var.s3_configs_bucket_id
  effective_s3_configs_bucket_arn = local.control_plane_config_bucket_arn != "" ? local.control_plane_config_bucket_arn : var.s3_configs_bucket_arn
  effective_s3_configs_prefix     = local.control_plane_config_prefix != "" ? local.control_plane_config_prefix : (var.s3_configs_prefix != "" ? var.s3_configs_prefix : "cp/v1/")

  effective_registry_url = var.registry_url != "" ? var.registry_url : try(local.control_plane_outputs.registry_url, "")
  registry_authority     = local.effective_registry_url != "" ? split("/", trimprefix(trimprefix(local.effective_registry_url, "https://"), "http://"))[0] : ""
  effective_registry_server_name = var.registry_server_name != "" ? var.registry_server_name : (
    local.registry_authority != "" ? split(":", local.registry_authority)[0] : ""
  )

  effective_step_ca_url                         = var.step_ca_url != "" ? var.step_ca_url : try(local.control_plane_outputs.step_ca_url, "")
  effective_step_ca_root_ca_secret_arn          = var.step_ca_root_ca_secret_arn != "" ? var.step_ca_root_ca_secret_arn : try(local.control_plane_outputs.step_ca_root_ca_secret_arn, "")
  effective_step_ca_provisioner                 = var.step_ca_provisioner != "" ? var.step_ca_provisioner : (try(local.control_plane_outputs.step_ca_provisioner_name, "") != "" ? try(local.control_plane_outputs.step_ca_provisioner_name, "") : "aws-iid")
  effective_registry_client_ca_secret_arn       = var.registry_client_ca_secret_arn != "" ? var.registry_client_ca_secret_arn : try(local.control_plane_outputs.registry_client_ca_secret_arn, "")
  effective_registry_bootstrap_token_secret_arn = var.registry_bootstrap_token_secret_arn != "" ? var.registry_bootstrap_token_secret_arn : try(local.control_plane_outputs.registry_bootstrap_token_secret_arn, "")

  # Node bootstrap always needs a trust root; prefer step-ca root when present.
  effective_registry_ca_secret_arn = local.effective_step_ca_root_ca_secret_arn != "" ? local.effective_step_ca_root_ca_secret_arn : local.effective_registry_client_ca_secret_arn
}

resource "terraform_data" "validate_control_plane_wiring" {
  lifecycle {
    precondition {
      condition = (
        !var.use_control_plane_remote_state ||
        local.control_plane_state_found ||
        (var.s3_configs_bucket_id != "" && var.s3_configs_bucket_arn != "")
      )
      error_message = format("control-plane state file not found at %s (from control_plane_state_path=%s). Apply control-plane first, set control_plane_state_path correctly, or provide s3_configs_bucket_id/s3_configs_bucket_arn manually.", local.control_plane_state_path_resolved, var.control_plane_state_path)
    }

    precondition {
      condition     = local.effective_s3_configs_bucket_id != "" && local.effective_s3_configs_bucket_arn != ""
      error_message = "s3_configs_bucket_id and s3_configs_bucket_arn are required (set explicitly or auto-wire from control-plane outputs)."
    }

    precondition {
      condition     = local.effective_s3_configs_prefix == "" || endswith(local.effective_s3_configs_prefix, "/")
      error_message = "Resolved configs prefix must end with '/'."
    }

    precondition {
      condition     = local.effective_registry_url != ""
      error_message = format("registry_url is required for node enrollment/heartbeat (set explicitly or auto-wire from control-plane outputs). If auto-wiring is enabled, verify control_plane_state_path resolves to %s and contains output registry_url.", local.control_plane_state_path_resolved)
    }

    precondition {
      condition     = local.effective_registry_server_name != ""
      error_message = format("registry_server_name could not be determined. Set registry_server_name explicitly or provide a valid registry_url. If auto-wiring is enabled, verify control_plane_state_path resolves to %s and contains output registry_url.", local.control_plane_state_path_resolved)
    }

    precondition {
      condition     = local.effective_registry_ca_secret_arn != ""
      error_message = "Registry trust root secret is required. Set step_ca_root_ca_secret_arn or registry_client_ca_secret_arn (or auto-wire from control-plane outputs)."
    }

    precondition {
      condition = (
        local.effective_step_ca_url != "" ||
        local.effective_registry_bootstrap_token_secret_arn != ""
      )
      error_message = "Node enrollment mode is incomplete. Set step_ca_url (preferred) or registry_bootstrap_token_secret_arn (legacy), or auto-wire from control-plane outputs."
    }
  }
}
