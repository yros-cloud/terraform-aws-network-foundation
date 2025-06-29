provider "aws" {
  region = "us-east-1"
}

module "network_foundation" {
  source  = "yroscloud/network-foundation/aws"
  version = "1.0.0"

  project     = "myproject"
  environment = "hub"
  region      = "us-east-1"

  az_count                    = 3
  vpc_transit_cidr            = "10.113.0.0/16"      # 65,536 IPs
  vpc_transit_public_base_cidr = "10.113.144.0/20"   # 1,024 IPs for public subnets
  subnet_newbits              = 3                   # Generates 8 subnets (/24)

  single_nat_gateway = true

  ram_principals = [
    "111122223333",
    "222233334444"
  ]

  vpc_attachments = {
    development = {
      cidr            = "10.120.0.0/16"
      route_table_ids = [] # to be filled in spoke modules
      account_id      = "111122223333"
    }
    production = {
      cidr            = "10.121.0.0/16"
      route_table_ids = []
      account_id      = "222233334444"
    }
  }

  tgw_routes_allow = [
    { from = "development", to = "production" },
    { from = "production", to = "development" }
  ]

  enable_vpc_flow_logs      = true
  vpc_flow_logs_bucket_name = "" # Leave empty to auto-create

  tags = {
    Owner       = "InfraTeam"
    Environment = "hub"
  }
}
