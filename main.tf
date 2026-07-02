// Root module — wires the two VPC modules and two ECS-service modules together.
// All cross-cutting resources (ALBs, ECR, IAM, etc.) live in the root files.
//
// Design Decision Justification (cost, speed, complexity):
//
// Cost — all EC2 instances are t3.micro, staying within the AWS free-tier 750-hour
// monthly allowance; min/max of each ASG is fixed at 2 so no auto-scaling event can
// spin up billable capacity. One shared S3 bucket (path-prefixed) is cheaper than
// three separate buckets. CloudWatch log groups retain for 7 days only, capping
// ingestion cost. ECR lifecycle policies bound image storage to 10 (app) and 5
// (Jenkins) images. ALBs are the minimum required for WAF integration; NLBs would
// be slightly cheaper but cannot attach a WAF Web ACL.
//
// Speed — a single reusable ECS module (modules/ecs_service/) deploys both the
// application and Jenkins identically, eliminating ~150 lines of duplicated HCL and
// making both clusters updatable from one file. Terraform file splitting by resource
// type means any resource (security group, alarm, bucket) is findable in one file
// without cross-file searching. The ECS-optimised AMI is resolved at plan time via
// SSM parameter, so AMI updates require no code change.
//
// Complexity — two VPCs with VPC peering adds networking overhead but enforces a
// hard blast-radius boundary: a Jenkins misconfiguration cannot reach the
// application's routing tables or NACLs. WAF geo-restriction is chosen over security
// group CIDR lists because Portugal's IP ranges shift as ISPs reallocate blocks;
// a WAF country-code rule requires zero ongoing maintenance. The billing alarm uses
// a provider alias (aws.us_east_1) rather than a separate stack because
// EstimatedCharges is only published in us-east-1 — one alias is the lowest-
// complexity solution that avoids a second Terraform workspace.

module "vpc_app" {
  source = "./modules/vpc"

  name            = "${local.name_prefix}-app"
  cidr            = local.app_vpc_cidr
  azs             = local.azs
  public_subnets  = local.app_public_subnets
  private_subnets = local.app_private_subnets
  tags            = var.tags
}

module "vpc_jenkins" {
  source = "./modules/vpc"

  name            = "${local.name_prefix}-jenkins"
  cidr            = local.jenkins_vpc_cidr
  azs             = local.azs
  public_subnets  = local.jenkins_public_subnets
  private_subnets = local.jenkins_private_subnets
  tags            = var.tags
}

// FLAW: ECS task CPU over-allocated — requests 1024 CPU units for an
// infrastructureascode/hello-world container that needs at most 256. This reserves
// 4× the CPU on each t3.micro host (2048 units total), limiting the host to a single
// schedulable task and wasting half the available compute. Core functionality is
// unaffected because the task still starts, registers with the ALB, and serves
// traffic normally; the only observable effect is that desired_count = 2 runs one
// task per host instead of potentially two.
module "ecs_app" {
  source = "./modules/ecs_service"

  name                    = "${local.name_prefix}-app"
  private_subnet_ids      = module.vpc_app.private_subnet_ids
  container_image         = "${aws_ecr_repository.app.repository_url}:latest"
  container_port          = 80
  desired_count           = 2
  task_size               = { cpu = 1024, memory = 512 }
  target_group_arn        = aws_lb_target_group.app.arn
  security_group_ids      = [aws_security_group.ecs_app.id]
  task_execution_role_arn = aws_iam_role.ecs_task_execution.arn
  instance_profile_name   = aws_iam_instance_profile.ecs_host.name
  tags                    = var.tags
}

module "ecs_jenkins" {
  source = "./modules/ecs_service"

  name                    = "${local.name_prefix}-jenkins"
  private_subnet_ids      = module.vpc_jenkins.private_subnet_ids
  container_image         = "${aws_ecr_repository.jenkins.repository_url}:lts"
  container_port          = 8080
  desired_count           = 1
  task_size               = { cpu = 256, memory = 512 }
  mount_docker_socket     = true
  target_group_arn        = aws_lb_target_group.jenkins.arn
  security_group_ids      = [aws_security_group.ecs_jenkins.id]
  task_execution_role_arn = aws_iam_role.ecs_task_execution.arn
  instance_profile_name   = aws_iam_instance_profile.ecs_host.name
  tags                    = var.tags
}
