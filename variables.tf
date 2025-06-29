variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones to use"
  type        = number
  default     = 3
}

variable "vpc_transit_cidr" {
  description = "CIDR block for the Transit VPC"
  type        = string
}

variable "vpc_transit_public_base_cidr" {
  description = "Base CIDR block for creating public subnets"
  type        = string
}

variable "subnet_newbits" {
  description = "Number of additional bits used to create subnets"
  type        = number
  default     = 4
}

variable "single_nat_gateway" {
  description = "Whether to use a single NAT Gateway or one per AZ"
  type        = bool
  default     = true
}

variable "ram_principals" {
  description = "List of AWS Account IDs allowed to access the shared Transit Gateway via AWS RAM"
  type        = list(string)
}

variable "tags" {
  description = "Map of custom tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_attachments" {
  description = "Map of VPCs that will be attached to the Transit Gateway"
  type = map(object({
    cidr            = string
    route_table_ids = list(string)
  }))
}

variable "tgw_routes_allow" {
  description = "List of allowed routing rules between VPCs via the Transit Gateway"
  type = list(object({
    from = string
    to   = string
  }))
}

variable "enable_vpc_flow_logs" {
  description = "If true, enables VPC Flow Logs"
  type        = bool
  default     = false
}

variable "vpc_flow_logs_bucket_name" {
  description = "Name of the S3 bucket to store VPC Flow Logs. If not defined, a new one will be created automatically."
  type        = string
  default     = ""
}
