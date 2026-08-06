# -----------------------------------------------------------------------------
# VPC, subnets, internet gateway, NAT gateway, S3 gateway endpoint
# -----------------------------------------------------------------------------

locals {
  # Nodes live in public subnets by default so the deployment needs no NAT
  # gateways. Set node_network_placement = "private" to restore NAT egress.
  node_subnets_are_public = var.node_network_placement == "public"
  node_subnet_ids         = local.node_subnets_are_public ? aws_subnet.public[*].id : aws_subnet.private[*].id

  nat_enabled = !local.node_subnets_are_public
  nat_count = local.nat_enabled ? (
    var.nat_gateway_mode == "single" ? 1 : length(var.availability_zones)
  ) : 0
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

# --- Public subnets (ALBs, NAT gateways, and nodes in public placement) ---

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-${var.availability_zones[count.index]}" }
}

# --- Private subnets (EC2 nodes in private placement) ---
#
# Always created. Subnets and route tables are free, and keeping them present
# means switching node_network_placement does not reshape the whole VPC.

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 100)
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${var.project_name}-private-${var.availability_zones[count.index]}" }
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

locals {
  # In "single" mode one gateway serves every AZ, so an AZ suffix would name a
  # zone the gateway is not specific to.
  nat_name_suffixes = var.nat_gateway_mode == "single" ? ["shared"] : var.availability_zones
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"

  tags = { Name = "${var.project_name}-nat-eip-${local.nat_name_suffixes[count.index]}" }
}

resource "aws_nat_gateway" "main" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = { Name = "${var.project_name}-nat-${local.nat_name_suffixes[count.index]}" }

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
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.main.id

  # No default route in public placement: the private subnets stay isolated and
  # unused rather than paying for a NAT gateway nothing routes through.
  dynamic "route" {
    for_each = local.nat_enabled ? [1] : []

    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[var.nat_gateway_mode == "single" ? 0 : count.index].id
    }
  }

  tags = { Name = "${var.project_name}-private-rt-${var.availability_zones[count.index]}" }
}

resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
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
    aws_route_table.private[*].id,
  )

  tags = { Name = "${var.project_name}-s3-endpoint" }
}
