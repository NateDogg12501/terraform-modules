variable "role_name" {
  description = "Name of the IAM role. Scope it to one repo and one environment (e.g. \"kids-ledger-prod-deploy\") — this module creates a role per repo per environment, not one shared role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters from the IAM name set: alphanumerics and +=,.@_-"
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the account's GitHub OIDC provider — the `provider_arn` output of the github-oidc-provider module."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN (arn:aws:iam::<account-id>:oidc-provider/...). Pass github-oidc-provider's provider_arn output."
  }
}

variable "github_repo" {
  description = <<-EOT
    The repository allowed to assume this role, as "owner/name" (e.g.
    "NateDogg12501/kids-ledger"). Case matters: GitHub puts the repository's
    canonical casing in the token's `sub` claim, and IAM condition matching is
    case-sensitive.

    Wildcards are rejected. Not a stylistic rule — subject_claims is validated
    by prefix against this value, so a wildcard here would defeat that check
    and hand the role to every repository on GitHub.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$", var.github_repo))
    error_message = "github_repo must be \"owner/name\" using only characters GitHub allows in each. In particular it must not contain * or ? — a wildcard here would defeat the subject_claims check."
  }
}

variable "subject_claims" {
  description = <<-EOT
    The `sub` claim patterns this role accepts, matched with StringLike (so *
    and ? are wildcards, and a pattern without either behaves as an exact
    match). This is the security boundary — see this module's README.

    Typical values:
      production: ["repo:owner/name:ref:refs/heads/main"]
      staging:    ["repo:owner/name:*"]

    Every entry must be scoped to github_repo; see the validation below.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.subject_claims) > 0
    error_message = "subject_claims must contain at least one pattern. An empty list produces a StringLike condition with no values, which no token can satisfy."
  }

  # The guard the whole module exists for. A `sub` pattern that isn't anchored
  # to this repository is assumable by whatever else it does match — at the
  # extreme, "repo:*" is every repository on GitHub, public ones included, and
  # the resulting role looks completely normal in the console.
  #
  # Requiring the trailing colon is what makes the prefix exact:
  # "repo:owner/name-evil:*" does not start with "repo:owner/name:".
  validation {
    condition = alltrue([
      for claim in var.subject_claims : startswith(claim, "repo:${var.github_repo}:")
    ])
    error_message = "Every subject_claims entry must start with \"repo:${var.github_repo}:\" — a pattern not anchored to this repository would let other repositories assume this role."
  }
}

variable "permissions_boundary_arn" {
  description = <<-EOT
    ARN of the permissions boundary policy attached to the role. **Required, on
    purpose — there is no default.**

    A boundary caps what the role can ever do, whatever policy_json says and
    whatever it is granted later. These roles get created by an automated
    provisioner, so an optional argument means one forgotten line produces an
    unbounded deploy role that nothing complains about. Required means the
    plan fails instead.

    This module consumes the boundary; it does not create it. That policy is
    account-scoped and belongs in the account bootstrap config.
  EOT
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be an IAM policy ARN (arn:aws:iam::<account-id>:policy/... or an AWS-managed arn:aws:iam::aws:policy/...). A role ARN or an empty string will not do."
  }
}

variable "iam_path" {
  description = "IAM path for the role. Grouping every CI-provisioned deploy role under one path makes them selectable as a set — e.g. a boundary or SCP that constrains arn:aws:iam::*:role/project-deploy/*."
  type        = string
  default     = "/project-deploy/"

  validation {
    condition     = can(regex("^/([A-Za-z0-9+=,.@_-]+/)*$", var.iam_path))
    error_message = "iam_path must begin and end with \"/\" (\"/\" itself is valid)."
  }
}

variable "policy_json" {
  description = <<-EOT
    The permissions this role actually gets, as an IAM policy JSON document —
    typically from an aws_iam_policy_document data source in the caller.
    Attached as an inline policy, so it is deleted along with the role rather
    than being left behind as an orphaned managed policy.

    Whatever this grants is still capped by permissions_boundary_arn.
  EOT
  type        = string

  validation {
    condition     = can(jsondecode(var.policy_json))
    error_message = "policy_json must be valid JSON. Pass data.aws_iam_policy_document.<name>.json, or jsonencode({...})."
  }
}

variable "max_session_duration" {
  description = "Maximum lifetime, in seconds, of the credentials a workflow run receives (3600-43200). The default hour is plenty for a deploy; raise it only if a single job genuinely runs longer, since it also widens the window a leaked credential is useful for."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds (IAM's own limits)."
  }
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}
