variable "thumbprint_list" {
  description = <<-EOT
    Server certificate thumbprints for the GitHub OIDC endpoint. Leave null
    (the default) — AWS validates token.actions.githubusercontent.com against
    its own trusted root CA store and ignores whatever is here. See main.tf for
    the full reasoning; this variable exists only as an escape hatch if that
    ever stops being true.
  EOT
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Tags applied to the OIDC provider."
  type        = map(string)
  default     = {}
}
