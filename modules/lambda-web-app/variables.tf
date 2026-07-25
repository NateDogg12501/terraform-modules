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
