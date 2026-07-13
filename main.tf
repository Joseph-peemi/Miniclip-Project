// This is where the two VPC modules and two ECS-service modules actually get
// wired together. Everything that cuts across both stacks — ALBs, ECR, IAM —
// lives in the root files rather than being duplicated per-service.
//
// A few notes on why things are shaped this way:
//
// Cost: every EC2 instance is t3.micro, and each ASG is pinned min=max=2 so
// nothing can scale up into billable territory on its own. The three log
// streams share one S3 bucket instead of three, log groups only keep 7 days,
// and ECR lifecycle rules cap image storage at 10 (app) / 5 (Jenkins). ALBs
// were picked over NLBs mainly because NLBs can't attach a WAF Web ACL —
// otherwise NLBs would've been the cheaper option.
//
// Speed of iteration: modules/ecs_service/ is used twice — once for the app,
// once for Jenkins — instead of writing out the ECS resources twice. That
// alone cuts something like 150 lines of duplicated HCL and means both
// clusters get updated from a single file. Resources are also split across
// files by type (security groups, alarms, buckets, ...) so you're not hunting
// across the whole repo for one thing. The AMI is resolved via SSM parameter
// at plan time, so a new ECS-optimized AMI never requires a code change here.
//
// Why the extra complexity of two peered VPCs: it buys a hard blast-radius
// boundary — a Jenkins misconfiguration physically can't reach the app VPC's
// routes or NACLs. Portugal geo-restriction goes through WAF rather than
// security-group CIDR lists because Portuguese IP ranges shift over time as
// ISPs reallocate blocks; a WAF country-code rule just doesn't need upkeep.
// And the billing alarm reuses a provider alias (aws.us_east_1) instead of a
// second Terraform workspace, since EstimatedCharges is only ever published
// in us-east-1 — the alias is the smallest change that gets us there.

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

// FLAW 1: this task asks for 1024 CPU units, but the hello-world container
// running here barely needs 256. Each t3.micro host only has 2048 units total,
// so this one task eats a full quarter of the host and leaves no room to
// schedule a second one — half the cluster's compute just sits unused.
// Nothing actually breaks: the task starts fine, registers with the ALB, and
// serves traffic normally. The only symptom is that desired_count = 2 ends up
// placing one task per host instead of doubling up where it could.
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
