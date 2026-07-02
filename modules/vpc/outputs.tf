output "vpc_id" {
  description = "ID of the VPC"
  value       = module.this.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.this.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the 2 public subnets (ALB placement)"
  value       = module.this.public_subnets
}

output "private_subnet_ids" {
  description = "IDs of the 2 private subnets (ECS cluster / EC2 host placement)"
  value       = module.this.private_subnets
}

output "private_route_table_ids" {
  description = "Route table IDs for the private subnets, used for VPC peering routes"
  value       = module.this.private_route_table_ids
}
