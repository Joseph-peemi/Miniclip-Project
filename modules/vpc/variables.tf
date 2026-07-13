// Gets prefixed onto everything this VPC creates — e.g. "app" or "jenkins"
variable "name" {
  type        = string
  description = "Name prefix for the VPC and its resources"
}

// 10.40.0.0/16 for the app VPC, 10.41.0.0/16 for Jenkins
variable "cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

// Needs to line up 1:1 with the subnet lists below, or the module will complain
variable "azs" {
  type        = list(string)
  description = "Availability zones to spread subnets across (length must match subnet lists)"
}

// Just the ALB lives here — nothing else needs a public subnet
variable "public_subnets" {
  type        = list(string)
  description = "CIDR blocks for the 2 public subnets"
}

// Where the ECS cluster and its EC2 hosts sit — no route straight to the internet
variable "private_subnets" {
  type        = list(string)
  description = "CIDR blocks for the 2 private subnets"
}

// Same tag shape used everywhere else in this repo
variable "tags" {
  type = object({
    environment = optional(string, "develop")
    product     = optional(string, "cloud")
    service     = optional(string, "pipeline")
  })
  default     = {}
  description = "Standard resource tags, merged with provider default_tags"
}
