# -----------------------------------------------------------------------------
# VPC, subnets, internet gateway, NAT gateway, S3 gateway endpoint
# -----------------------------------------------------------------------------

locals {
  # Subnets are keyed by availability zone rather than by list position, and
  # each AZ's CIDR is derived from the AZ name rather than its index in
  # var.availability_zones. Both matter: with positional keys and index-derived
  # CIDRs, adding, removing, or reordering an AZ renumbers every AZ after it,
  # which forces subnet replacement and fails with InvalidSubnet.Conflict
  # because the new subnet wants a CIDR the old one still holds.
  #
  # With this scheme an AZ always gets the same CIDR, so changing the AZ list
  # only creates or destroys the subnets for the AZs that were actually added
  # or removed.
  az_letters = ["a", "b", "c", "d", "e", "f", "g", "h"]
  az_slots   = { for az in var.availability_zones : az => index(local.az_letters, substr(az, -1, 1)) }

  azs_sorted = sort(var.availability_zones)

  # Nodes live in public subnets by default so the deployment needs no NAT
  # gateways. Set node_network_placement = "private" to restore NAT egress.
  node_subnets_are_public = var.node_network_placement == "public"
  node_subnet_ids = [
    for az in local.azs_sorted :
    (local.node_subnets_are_public ? aws_subnet.public[az].id : aws_subnet.private[az].id)
  ]

  nat_enabled = !local.node_subnets_are_public

  # "single" uses a fixed "shared" key rather than the first AZ's name, so the
  # gateway is never labelled with an availability zone it is not specific to.
  nat_keys = !local.nat_enabled ? [] : (
    var.nat_gateway_mode == "single" ? ["shared"] : local.azs_sorted
  )
  nat_primary_az = local.azs_sorted[0]
}

# Region/AZ agreement is checked here rather than in a variable validation
# block: referencing another variable inside validation requires Terraform 1.9,
# and this stack supports >= 1.5.
resource "terraform_data" "validate_network" {
  lifecycle {
    precondition {
      condition     = alltrue([for az in var.availability_zones : startswith(az, var.aws_region)])
      error_message = "Every availability_zones entry must belong to aws_region (${var.aws_region})."
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

# --- Public subnets (ALBs, NAT gateways, and nodes in public placement) ---

resource "aws_subnet" "public" {
  for_each = toset(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, local.az_slots[each.key])
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-${each.key}" }
}

# --- Private subnets (EC2 nodes in private placement) ---
#
# Always created. Subnets and route tables are free, and keeping them present
# means switching node_network_placement does not reshape the whole VPC.

resource "aws_subnet" "private" {
  for_each = toset(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, local.az_slots[each.key] + 100)
  availability_zone = each.key

  tags = { Name = "${var.project_name}-private-${each.key}" }
}

# --- Internet gateway ---

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-igw" }
}

# --- NAT gateways (only in private placement) ---
#
# nat_gateway_mode = "per_az" keeps one gateway per availability zone so a
# single AZ failure cannot take node egress down. "single" creates one gateway
# for cost-sensitive deployments, at the cost of an AZ dependency and cross-AZ
# data charges for non-S3 egress from the other zones.

resource "aws_eip" "nat" {
  for_each = toset(local.nat_keys)

  domain = "vpc"

  tags = { Name = "${var.project_name}-nat-eip-${each.key}" }
}

resource "aws_nat_gateway" "main" {
  for_each = toset(local.nat_keys)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key == "shared" ? local.nat_primary_az : each.key].id

  tags = { Name = "${var.project_name}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.main]
}

# --- Route tables ---

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = toset(var.availability_zones)

  vpc_id = aws_vpc.main.id

  # No default route in public placement: the private subnets stay isolated and
  # unused rather than paying for a NAT gateway nothing routes through.
  dynamic "route" {
    for_each = local.nat_enabled ? [1] : []

    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[var.nat_gateway_mode == "single" ? "shared" : each.key].id
    }
  }

  tags = { Name = "${var.project_name}-private-rt-${each.key}" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# --- S3 gateway endpoint ---
#
# Gateway endpoints have no hourly or per-GB charge. Node bootstrap syncs the
# rootfs image set from S3 and polls S3 for configuration, and Amazon Linux
# package repositories are served from regional S3, so this keeps that traffic
# off NAT entirely in private placement.
#
# Gateway endpoints only serve buckets in the same region as this VPC. The
# images and configs buckets come from the control-plane stack, which has its
# own region variable — a split-region deployment silently bypasses the
# endpoint with no error. See the data-plane README.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # Associated with both route tables so the endpoint applies in either
  # node_network_placement without needing to be reshaped.
  route_table_ids = concat(
    [aws_route_table.public.id],
    [for rt in aws_route_table.private : rt.id],
  )

  tags = { Name = "${var.project_name}-s3-endpoint" }
}
