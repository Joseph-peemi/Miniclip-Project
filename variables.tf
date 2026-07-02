// Root input variables (req. 7: object-typed tags; req. 13.x: sizing/count controls)

variable "tags" {
  type = object({
    environment = optional(string, "develop")
    product     = optional(string, "cloud")
    service     = optional(string, "pipeline")
  })
  default     = {}
  description = "Standard resource tags applied to all resources via the provider default_tags block"
}

variable "alert_email" {
  type        = string
  description = "Email address for SNS alert notifications"
}

// Both ALB HTTPS listeners share one cert — the cert must cover the app and Jenkins domains.
// Request a free public cert in ACM and verify domain ownership before running terraform apply.
variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS listeners on both ALBs (must be in eu-central-1)"
}
