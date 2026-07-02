// Name prefix for the VPC and everything inside it (e.g. "app", "jenkins")
variable "name" {
  type        = string
  description = "Name prefix for the VPC and its resources"
}

// Primary CIDR block for this VPC (10.40.0.0/16 for app, 10.41.0.0/16 for Jenkins per req. 2)
variable "cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

// Availability zones the subnets are spread across
variable "azs" {
  type        = list(string)
  description = "Availability zones to spread subnets across (length must match subnet lists)"
}

// 2 public subnets — hold only the ALB, nothing else lives here (req. 13.2)
variable "public_subnets" {
  type        = list(string)
  description = "CIDR blocks for the 2 public subnets"
}

// 2 private subnets — hold the ECS cluster and EC2 hosts, no direct internet route (req. 13.2)
variable "private_subnets" {
  type        = list(string)
  description = "CIDR blocks for the 2 private subnets"
}

// Standard tag object with defaults — matches the org-wide tagging convention (req. 7)
variable "tags" {
  type = object({
    environment = optional(string, "develop")
    product     = optional(string, "cloud")
    service     = optional(string, "pipeline")
  })
  default     = {}
  description = "Standard resource tags, merged with provider default_tags"
}
