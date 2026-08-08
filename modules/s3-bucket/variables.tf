variable "bucket_name" {
  description = "Globally unique S3 bucket name (bucket names are a single global namespace across all AWS accounts)."
  type        = string
}

variable "versioning_enabled" {
  description = <<-EOT
    Enable object versioning. Recommended for anything you can't regenerate
    (e.g. Terraform state) since it turns an overwrite or delete into a
    recoverable noncurrent version instead of data loss. Versioning itself
    isn't billed separately, but every version is a full object copy that
    counts toward the 5GB Always Free storage allowance — see
    noncurrent_version_expiration_days below.
  EOT
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete this bucket even if it still has objects in it. Leave false for anything holding state or data you can't regenerate."
  type        = bool
  default     = false
}

variable "sse_algorithm" {
  description = <<-EOT
    Default server-side encryption applied to every object. "AES256" (SSE-S3,
    an AWS-owned key) is free. "aws:kms" requires cost_acknowledged = true —
    see this module's README for why.
  EOT
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be \"AES256\" or \"aws:kms\"."
  }
}

variable "kms_key_id" {
  description = "KMS key ARN/ID to encrypt with when sse_algorithm = \"aws:kms\". Ignored otherwise. Leave null to use the AWS-managed aws/s3 key."
  type        = string
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = <<-EOT
    Days to keep a noncurrent object version before it's permanently deleted.
    Only takes effect when versioning_enabled is true. 0 disables the rule,
    so noncurrent versions accumulate forever — on a bucket that gets a lot
    of overwrites (e.g. Terraform state, applied on every run) that will
    eventually exceed the 5GB Always Free storage allowance even though
    nothing about the configuration looks billable. Deletion itself is free
    either way.
  EOT
  type        = number
  default     = 90
}

variable "cost_acknowledged" {
  description = <<-EOT
    Set true to confirm you accept a billable configuration. The standard is
    AWS Always Free unless logged in docs/decisions.md and explicitly
    confirmed — this flag is the "explicitly confirmed" half, and the plan
    fails without it when sse_algorithm is not "AES256".
    Log the "why" in your project's docs/decisions.md; setting this to true
    without that entry satisfies the mechanism but not the standard.
  EOT
  type        = bool
  default     = false
}
