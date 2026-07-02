# vpc

Thin wrapper around `terraform-aws-modules/vpc/aws` (~> 6.0). Called twice from
root `main.tf` — once for the application VPC (`10.40.0.0/16`) and once for the
Jenkins VPC (`10.41.0.0/16`) — each with 2 public and 2 private subnets across
2 AZs in `eu-central-1`, per the org's VPC/subnet standard.

No resources are defined directly in this module; it exists to keep both call
sites in root `main.tf` consistent and to expose only the outputs the rest of
the stack needs (VPC ID, subnet IDs, private route table IDs for peering).

## Usage

```hcl
module "vpc_app" {
  source          = "./modules/vpc"
  name            = "app"
  cidr            = "10.40.0.0/16"
  azs             = ["eu-central-1a", "eu-central-1b"]
  public_subnets  = ["10.40.0.0/24", "10.40.1.0/24"]
  private_subnets = ["10.40.2.0/24", "10.40.3.0/24"]
  tags            = var.tags
}
```

## Inputs

| Name | Type | Description |
|---|---|---|
| name | string | Name prefix |
| cidr | string | VPC CIDR block |
| azs | list(string) | Availability zones |
| public_subnets | list(string) | Public subnet CIDRs (2) |
| private_subnets | list(string) | Private subnet CIDRs (2) |
| tags | object | Standard tag object (see variables.tf) |

## Outputs

| Name | Description |
|---|---|
| vpc_id | VPC ID |
| vpc_cidr_block | VPC CIDR |
| public_subnet_ids | Public subnet IDs |
| private_subnet_ids | Private subnet IDs |
| private_route_table_ids | Private route table IDs (needed for peering) |
