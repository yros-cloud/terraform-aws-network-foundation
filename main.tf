data "aws_availability_zones" "available" {}

locals {
  tags = merge(
    var.tags,
    {
      CreatedBy = "Terraform"
      Module    = "aws-network-foundation-transit-gateway"
    }
  )

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  private_subnets = cidrsubnets(var.vpc_transit_cidr, var.subnet_newbits, var.az_count)
  public_subnets = [
    for i in range(var.az_count) :
    cidrsubnet(var.vpc_transit_public_base_cidr, var.subnet_newbits, i)
  ]
}

# 🔁 Spoke → Spoke allowed routes (defined in tgw_routes_allow)
locals {
  allowed_routes = flatten([
    for r in var.tgw_routes_allow : [
      for rt_id in var.vpc_attachments[r.from].route_table_ids : {
        key                    = "${r.from}->${r.to}->${rt_id}"
        route_table_id         = rt_id
        destination_cidr_block = var.vpc_attachments[r.to].cidr
      }
    ]
  ])
}

# 📘 All route table IDs in the Transit VPC
locals {
  transit_route_table_ids = concat(
    module.vpc_transit.private_route_table_ids,
    module.vpc_transit.public_route_table_ids
  )

  transit_to_spoke_routes = {
    for spoke_key, spoke in var.vpc_attachments :
    spoke_key => spoke.cidr
  }
}

# 📍 Each Transit VPC route to each spoke CIDR
locals {
  transit_spoke_routes = {
    for pair in flatten([
      for rt_id in local.transit_route_table_ids : [
        for spoke_key, cidr in local.transit_to_spoke_routes : {
          key                    = "${rt_id}-${spoke_key}"
          route_table_id         = rt_id
          destination_cidr_block = cidr
        }
      ]
    ]) : pair.key => pair
  }
}

# 📡 Unique RAM principals from VPC attachments
locals {
  ram_principals = distinct([
    for vpc in values(var.vpc_attachments) : vpc.account_id
  ])
}


# 🌐 Transit Gateway module
module "tgw" {
  source  = "terraform-aws-modules/transit-gateway/aws"
  version = "2.13.0"

  name        = "${var.project}-tgw-${var.environment}"
  description = "${var.project} Transit Gateway shared across environments"

  enable_auto_accept_shared_attachments = true
  ram_allow_external_principals         = true
  ram_principals                        = local.ram_principals

  tags = merge({ "Name" = "${var.project}-tgw-${var.environment}" }, local.tags)
}

# 🚀 Transit VPC module
module "vpc_transit" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.0.1"

  name = "${var.project}-vpc-transit-${var.environment}"
  cidr = var.vpc_transit_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_support   = true
  enable_dns_hostnames = true
  
  enable_flow_log               = var.enable_vpc_flow_logs
  flow_log_destination_type     = "s3"
  flow_log_destination_arn      = var.vpc_flow_logs_bucket_name != "" ? "arn:aws:s3:::${var.vpc_flow_logs_bucket_name}" : try(aws_s3_bucket.vpc_flow_logs[0].arn, null)

  flow_log_max_aggregation_interval = 60
  flow_log_traffic_type             = "ALL"

  tags = local.tags
}

# 🔗 TGW attachment to the Transit VPC
resource "aws_ec2_transit_gateway_vpc_attachment" "transit" {
  vpc_id             = module.vpc_transit.vpc_id
  subnet_ids         = module.vpc_transit.private_subnets
  transit_gateway_id = module.tgw.ec2_transit_gateway_id
  dns_support        = "enable"

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = merge({ "Name" = "${var.project}-transit-attachment-${var.environment}" }, local.tags)
}

# 🛣️ Default route 0.0.0.0/0 pointing to Transit VPC
resource "aws_ec2_transit_gateway_route" "default_to_transit_vpc" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.transit.id
  transit_gateway_route_table_id = module.tgw.ec2_transit_gateway_association_default_route_table_id
}

# 🛣️ Routes from Transit VPC to all spoke VPCs
resource "aws_route" "transit_to_spokes" {
  count = length(module.vpc_transit.private_route_table_ids) + length(module.vpc_transit.public_route_table_ids) * length(keys(var.vpc_attachments))

  route_table_id         = element(concat(module.vpc_transit.private_route_table_ids, module.vpc_transit.public_route_table_ids), floor(count.index / length(keys(var.vpc_attachments))))
  destination_cidr_block = element([for v in values(var.vpc_attachments) : v.cidr], count.index % length(keys(var.vpc_attachments)))
  transit_gateway_id     = module.tgw.ec2_transit_gateway_id

  lifecycle {
    ignore_changes = [route_table_id] # prevent unnecessary recreation
  }
}

# 📦 Optional bucket for VPC Flow Logs
resource "aws_s3_bucket" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs && var.vpc_flow_logs_bucket_name == "" ? 1 : 0

  bucket        = "${var.project}-vpc-flowlogs-${var.environment}"
  force_destroy = true

  tags = merge({ Name = "vpc-flow-logs" }, local.tags)
}

# 📤 Outputs
output "transit_gateway_id" {
  value = module.tgw.ec2_transit_gateway_id
}

output "transit_vpc_id" {
  value = module.vpc_transit.vpc_id
}

output "transit_nat_gateway_ips" {
  value = module.vpc_transit.nat_public_ips
}

output "vpc_flow_logs_bucket_name" {
  value = var.enable_vpc_flow_logs ? (
    var.vpc_flow_logs_bucket_name != "" ? var.vpc_flow_logs_bucket_name : aws_s3_bucket.vpc_flow_logs[0].bucket
  ) : ""
  description = "Name of the bucket used for VPC Flow Logs (if enabled)."
}
