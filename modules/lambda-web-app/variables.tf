variable "app_name" {
  description = "Name used for the Lambda function and its IAM role"
  type        = string
}

variable "source_dir" {
  description = "Directory containing the already-built Lambda artifact (e.g. \"../dist-lambda\"). This module zips it — it does not build it. Run your build step before `terraform apply`."
  type        = string
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs22.x"
}

variable "lambda_architecture" {
  description = "Lambda instruction set architecture (\"x86_64\" or \"arm64\")"
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "lambda_architecture must be \"x86_64\" or \"arm64\"."
  }
}

variable "lambda_web_adapter_layer_arn" {
  description = <<-EOT
    Lambda Web Adapter layer ARN. Leave unset to use a computed default
    (region + architecture, pinned to a specific adapter version) — check
    https://github.com/awslabs/aws-lambda-web-adapter/releases for the
    current version before relying on the default.
  EOT
  type        = string
  default     = null
}

variable "aws_region" {
  description = "Region this Lambda deploys into — only used to compute the default adapter layer ARN above, does not configure the provider (that's the root config's job)"
  type        = string
}

variable "memory_size" {
  description = "Lambda memory in MB"
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 10
}

variable "port" {
  description = "Port your app listens on inside the Lambda Web Adapter runtime"
  type        = string
  default     = "8080"
}

variable "health_check_path" {
  description = "Path the Lambda Web Adapter polls to consider the app ready"
  type        = string
  default     = "/api/health"
}

variable "retention_in_days" {
  description = <<-EOT
    Retention for this function's CloudWatch log group. Defaults to 14 days,
    not "forever": CloudWatch Logs' free tier is 5GB of ingestion/storage per
    month, and unbounded retention turns that into a bill that only ever grows.
    Set 0 for Never Expire if you genuinely need it — that is a cost decision,
    so log it in your project's docs/decisions.md.
  EOT
  type        = number
  default     = 14

  validation {
    # CloudWatch accepts only this fixed set — an arbitrary number (say 10)
    # is rejected by the API at apply time, well after the plan looked fine.
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.retention_in_days
    )
    error_message = "retention_in_days must be one of CloudWatch's accepted values: 0 (never expire), 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}

variable "environment_variables" {
  description = "Plain (non-secret) environment variables to set on the function"
  type        = map(string)
  default     = {}
}

variable "ssm_secret_env_vars" {
  description = <<-EOT
    Map of env-var-name => SSM SecureString parameter path. Each parameter's
    decrypted value is injected as that environment variable. Terraform only
    reads these — it never creates or owns their value. Create each one
    yourself first:
      aws ssm put-parameter --name "<path>" --type SecureString --value "..."
  EOT
  type        = map(string)
  default     = {}
}
