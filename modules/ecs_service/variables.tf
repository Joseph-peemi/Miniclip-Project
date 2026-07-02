// Name prefix for this service's resources — "app" or "jenkins" (req. 3)
variable "name" {
  type        = string
  description = "Name prefix for the ECS cluster/service/task"
}

// Private subnets only — the cluster's EC2 hosts never sit in a public subnet (req. 13.2)
variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the ECS cluster's EC2 hosts"
}

// Container image — infrastructureascode/hello-world for app, jenkins/jenkins:lts for Jenkins
variable "container_image" {
  type        = string
  description = "Docker image for the ECS task"
}

// Port the container listens on
variable "container_port" {
  type        = number
  default     = 80
  description = "Container port registered with the ALB target group"
}

// 2 containers for the app, 1 for Jenkins (req. 13.3)
variable "desired_count" {
  type        = number
  default     = 1
  description = "Desired number of running tasks"
}

// Task-level compute sizing, object type with defaults per org standard (req. 7)
variable "task_size" {
  type = object({
    cpu    = optional(number, 256)
    memory = optional(number, 512)
  })
  default     = {}
  description = "CPU units / memory (MiB) for the task definition (req. 13.3: e.g. 256/512)"
}

// Free-tier EC2 only (Technical Scope: t3.micro)
variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type backing the ECS cluster"
}

// 2 EC2 instances per cluster (Technical Scope)
variable "instance_count" {
  type        = number
  default     = 2
  description = "Number of EC2 instances in the ECS cluster"
}

// ALB target group this service registers with
variable "target_group_arn" {
  type        = string
  description = "ARN of the ALB target group to attach the service to"
}

// Security groups applied to the ECS EC2 hosts
variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for the ECS EC2 instances"
}

// IAM is created in root iam.tf and passed in — keeps this module free of IAM opinions
variable "task_execution_role_arn" {
  type        = string
  description = "IAM role ARN the ECS agent uses to pull images and write logs"
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile attached to the EC2 container hosts"
}

variable "mount_docker_socket" {
  type        = bool
  default     = false
  description = "Mount /var/run/docker.sock from the EC2 host into the container (Jenkins only)"
}

variable "tags" {
  type = object({
    environment = optional(string, "develop")
    product     = optional(string, "cloud")
    service     = optional(string, "pipeline")
  })
  default     = {}
  description = "Standard resource tags"
}
