# -----------------------------------------------------------------------------
# AMI resolution for Firecracker nodes
# -----------------------------------------------------------------------------

data "aws_ami" "node_by_name" {
  count       = var.node_ami_name_pattern != "" ? 1 : 0
  most_recent = true
  owners      = var.node_ami_owners

  filter {
    name   = "name"
    values = [local.node_ami_name_filter]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = [var.node_ami_architecture]
  }
}

locals {
  packer_manifest_path_expanded = pathexpand(var.packer_manifest_path)
  packer_manifest_path_resolved = startswith(local.packer_manifest_path_expanded, "/") ? local.packer_manifest_path_expanded : abspath("${path.module}/${local.packer_manifest_path_expanded}")
  packer_manifest_found         = var.use_packer_manifest_ami && fileexists(local.packer_manifest_path_resolved)

  packer_manifest_builds = local.packer_manifest_found ? try(jsondecode(file(local.packer_manifest_path_resolved)).builds, []) : []
  packer_manifest_region_ami_ids = [
    for build in local.packer_manifest_builds :
    trimprefix(try(build.artifact_id, ""), "${var.aws_region}:")
    if startswith(try(build.artifact_id, ""), "${var.aws_region}:ami-")
  ]
  packer_manifest_latest_ami_id = length(local.packer_manifest_region_ami_ids) > 0 ? local.packer_manifest_region_ami_ids[length(local.packer_manifest_region_ami_ids) - 1] : ""

  node_ami_name_has_wildcards = length(regexall("[*?]", var.node_ami_name_pattern)) > 0
  node_ami_name_filter = var.node_ami_name_pattern == "" ? "" : (
    local.node_ami_name_has_wildcards ? var.node_ami_name_pattern : format("*%s*", var.node_ami_name_pattern)
  )

  effective_node_ami_id = var.node_ami_id != "" ? var.node_ami_id : (
    var.node_ami_name_pattern != "" ? try(data.aws_ami.node_by_name[0].id, "") : local.packer_manifest_latest_ami_id
  )
}

resource "terraform_data" "validate_node_ami" {
  lifecycle {
    precondition {
      condition = local.effective_node_ami_id != ""
      error_message = format(
        "No node AMI could be resolved. Set node_ami_id explicitly, set node_ami_name_pattern (latest match in AWS), or enable use_packer_manifest_ami with a valid manifest at %s (from packer_manifest_path=%s) containing an artifact for aws_region=%s.",
        local.packer_manifest_path_resolved,
        var.packer_manifest_path,
        var.aws_region,
      )
    }
  }
}
