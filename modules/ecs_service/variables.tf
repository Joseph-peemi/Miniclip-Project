// Whatever calls this module names its own service — "app" or "jenkins"
variable "name" {
  type        = string
  description = "Name prefix for the ECS cluster/service/task"
}

// Always private — the EC2 hosts backing this cluster never sit in a public subnet
variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the ECS cluster's EC2 hosts"
}

// infrastructureascode/hello-world for the app, jenkins/jenkins:lts for Jenkins
variable "container_image" {
  type        = string
  description = "Docker image for the ECS task"
}

// What port the container actually listens on
variable "container_port" {
  type        = number
  default     = 80
  description = "Container port registered with the ALB target group"
}

// 2 for the app, 1 for Jenkins — set by whoever calls the module
variable "desired_count" {
  type        = number
  default     = 1
  description = "Desired number of running tasks"
}

// CPU/memory for the task definition — the defaults are sane, callers override as needed
variable "task_size" {
  type = object({
    cpu    = optional(number, 256)
    memory = optional(number, 512)
  })
  default     = {}
  description = "CPU units / memory (MiB) for the task definition (req. 13.3: e.g. 256/512)"
}

// Sticking to t3.micro so this stays inside the free tier
variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type backing the ECS cluster"
}

// 2 hosts per cluster keeps us within the free-tier hour budget
variable "instance_count" {
  type        = number
  default     = 2
  description = "Number of EC2 instances in the ECS cluster"
}

// Which ALB target group this service should register itself with
variable "target_group_arn" {
  type        = string
  description = "ARN of the ALB target group to attach the service to"
}

// Applied to the EC2 hosts, not the containers
variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for the ECS EC2 instances"
}

// Created back in root iam.tf and passed in here — keeps IAM decisions out of this module
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
