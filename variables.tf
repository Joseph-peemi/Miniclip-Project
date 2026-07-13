// Top-level inputs for the whole stack — tagging, alerting, and the shared cert

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

// Both ALBs share this one cert, so it needs to cover both the app and Jenkins
// domains. Request it in ACM and get domain ownership verified before you apply.
variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS listeners on both ALBs (must be in eu-central-1)"
}
