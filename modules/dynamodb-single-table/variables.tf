variable "table_name" {
  type = string
}

variable "hash_key" {
  description = "Attribute name used as the table's partition key"
  type        = string
}

variable "range_key" {
  description = "Attribute name used as the table's sort key, if any"
  type        = string
  default     = null
}

variable "attributes" {
  description = <<-EOT
    Every attribute referenced by the table's own hash/range key OR by any
    global_secondary_indexes entry below. This mirrors DynamoDB's own API
    (attribute type declarations are separate from key schema) — list each
    attribute once regardless of how many indexes use it.
    Example: [{ name = "id", type = "S" }, { name = "createdAt", type = "N" }]
  EOT
  type = list(object({
    name = string
    type = string # "S" | "N" | "B"
  }))
}

variable "billing_mode" {
  type    = string
  default = "PROVISIONED"

  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.billing_mode)
    error_message = "billing_mode must be \"PROVISIONED\" or \"PAY_PER_REQUEST\"."
  }
}

variable "read_capacity" {
  description = "Base table read capacity units (PROVISIONED mode only)"
  type        = number
  default     = 5
}

variable "write_capacity" {
  description = "Base table write capacity units (PROVISIONED mode only)"
  type        = number
  default     = 5
}

variable "global_secondary_indexes" {
  description = "Optional GSIs. hash_key/range_key here must also appear in var.attributes."
  type = list(object({
    name           = string
    hash_key       = string
    range_key      = optional(string)
    projection_type = optional(string, "ALL")
    read_capacity  = optional(number, 5)
    write_capacity = optional(number, 5)
  }))
  default = []
}
