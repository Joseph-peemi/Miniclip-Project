# ecs_service

Reusable module (req. 3) that deploys an ECS-on-EC2 service — cluster,
free-tier EC2 capacity, task definition, and service registered against an
ALB target group. Called twice from root `main.tf`: once for the application
and once for Jenkins, each with different image, task size, and subnet inputs.

IAM roles and the ALB/target group are created in root (`iam.tf`, `alb.tf`)
and passed in, so this module stays focused on ECS/EC2 and can be reused for
either workload without carrying IAM opinions.

## Usage

```hcl
module "ecs_app" {
  source                   = "./modules/ecs_service"
  name                     = "app"
  private_subnet_ids       = module.vpc_app.private_subnet_ids
  container_image          = "infrastructureascode/hello-world"
  desired_count             = 2
  task_size                 = { cpu = 1024, memory = 2048 } # FLAW — see main.tf
  target_group_arn          = aws_lb_target_group.app.arn
  security_group_ids        = [aws_security_group.ecs_app.id]
  task_execution_role_arn   = aws_iam_role.ecs_execution.arn
  instance_profile_name     = aws_iam_instance_profile.ecs_app.name
  tags                      = var.tags
}

module "ecs_jenkins" {
  source                   = "./modules/ecs_service"
  name                     = "jenkins"
  private_subnet_ids       = module.vpc_jenkins.private_subnet_ids
  container_image          = "jenkins/jenkins:lts"
  desired_count             = 1
  target_group_arn          = aws_lb_target_group.jenkins.arn
  security_group_ids        = [aws_security_group.ecs_jenkins.id]
  task_execution_role_arn   = aws_iam_role.ecs_execution.arn
  instance_profile_name     = aws_iam_instance_profile.ecs_jenkins.name
  tags                      = var.tags
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| name | string | — | Resource name prefix |
| private_subnet_ids | list(string) | — | Private subnets for EC2 hosts |
| container_image | string | — | Image to run |
| container_port | number | 80 | Container port |
| desired_count | number | 1 | Running task count |
| task_size | object | `{cpu=256, memory=512}` | Task CPU/memory |
| instance_type | string | `t3.micro` | EC2 instance type |
| instance_count | number | 2 | EC2 hosts per cluster |
| target_group_arn | string | — | ALB target group |
| security_group_ids | list(string) | — | SGs for EC2 hosts |
| task_execution_role_arn | string | — | ECS execution role |
| instance_profile_name | string | — | EC2 instance profile |
| tags | object | see variables.tf | Standard tags |

## Outputs

| Name | Description |
|---|---|
| cluster_id | ECS cluster ID |
| cluster_name | ECS cluster name |
| service_name | ECS service name |
| task_definition_arn | Task definition ARN |

## Known flaw (Terraform)

The app call site intentionally over-allocates task CPU/memory relative to
what `infrastructureascode/hello-world` needs (1024/2048 vs. the 256/512
default). This wastes free-tier capacity but does not break functionality —
see the `FLAW` comment in `main.tf`.
