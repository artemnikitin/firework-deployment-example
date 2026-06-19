# -----------------------------------------------------------------------------
# Network for control-plane ECS services
# -----------------------------------------------------------------------------

locals {
  controlplane_public_subnets = {
    for index, cidr in var.public_subnet_cidrs :
    cidr => var.availability_zones[index]
    if index < length(var.availability_zones)
  }
}

resource "terraform_data" "validate_network_inputs" {
  lifecycle {
    precondition {
      condition     = length(var.public_subnet_cidrs) > 0
      error_message = "public_subnet_cidrs must contain at least one subnet CIDR."
    }

    precondition {
      condition     = length(local.controlplane_public_subnets) == length(var.public_subnet_cidrs)
      error_message = "availability_zones must contain at least as many entries as public_subnet_cidrs."
    }

    precondition {
      condition     = length(local.controlplane_public_subnets) >= 2
      error_message = "At least two public subnets are required for the events ALB."
    }

    precondition {
      condition     = length(distinct(values(local.controlplane_public_subnets))) >= 2
      error_message = "public_subnet_cidrs must span at least two distinct availability_zones."
    }
  }
}

resource "aws_vpc" "controlplane" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-controlplane-vpc" }
}

resource "aws_internet_gateway" "controlplane" {
  vpc_id = aws_vpc.controlplane.id

  tags = { Name = "${var.project_name}-controlplane-igw" }
}

resource "aws_subnet" "public" {
  for_each = local.controlplane_public_subnets

  vpc_id                  = aws_vpc.controlplane.id
  cidr_block              = each.key
  availability_zone       = each.value
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-controlplane-public-${each.value}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.controlplane.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.controlplane.id
  }

  tags = { Name = "${var.project_name}-controlplane-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
