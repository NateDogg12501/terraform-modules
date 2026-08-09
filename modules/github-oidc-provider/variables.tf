variable "thumbprint_list" {
  description = <<-EOT
    Server certificate thumbprints for the GitHub OIDC endpoint. Leave null
    (the default) — AWS validates token.actions.githubusercontent.com against
    its own trusted root CA store and ignores whatever is here. See main.tf for
    the full reasoning; this variable exists only as an escape hatch if that
    ever stops being true.

    One-way door if you do use it: the argument is Optional+Computed, so
    setting a thumbprint and later removing it leaves the original value in
    place rather than handing the decision back to AWS. Undoing it means
    setting the value you want explicitly, or replacing the provider.
  EOT
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Tags applied to the OIDC provider."
  type        = map(string)
  default     = {}
}
