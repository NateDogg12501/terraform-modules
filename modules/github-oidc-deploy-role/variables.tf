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

    Wildcards are rejected — a wildcard here would widen the subject prefix
    this module builds, which is the one thing standing between this role and
    every repository on GitHub.

    Names alone no longer identify a repository in the `sub` claim; see
    github_owner_id and github_repo_id.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$", var.github_repo))
    error_message = "github_repo must be \"owner/name\" using only characters GitHub allows in each. In particular it must not contain * or ? — a wildcard here would widen the subject prefix and hand the role to other repositories."
  }
}

variable "github_owner_id" {
  description = <<-EOT
    Numeric ID of the repository owner, which GitHub embeds in the `sub`
    claim. Find it with:

      gh api users/<owner> --jq .id        # or orgs/<owner> for an org

    This is not cosmetic. GitHub's subject claim is
    "repo:<owner>@<owner_id>/<name>@<repo_id>:...", so a trust policy built
    without the IDs matches no token that GitHub will ever mint, and the
    failure surfaces only as "Not authorized to perform
    sts:AssumeRoleWithWebIdentity".
  EOT
  type        = number

  validation {
    condition     = var.github_owner_id > 0 && floor(var.github_owner_id) == var.github_owner_id
    error_message = "github_owner_id must be a positive integer — the numeric id from `gh api users/<owner> --jq .id`."
  }
}

variable "github_repo_id" {
  description = <<-EOT
    Numeric ID of the repository itself, which GitHub embeds in the `sub`
    claim. Find it with:

      gh api repos/<owner>/<name> --jq .id

    Using the ID rather than the name is what makes the trust survive a
    rename and refuse an impersonation: a repository deleted and recreated
    under the same name gets a new ID, so it cannot inherit this role.
  EOT
  type        = number

  validation {
    condition     = var.github_repo_id > 0 && floor(var.github_repo_id) == var.github_repo_id
    error_message = "github_repo_id must be a positive integer — the numeric id from `gh api repos/<owner>/<name> --jq .id`."
  }
}

variable "subject_suffixes" {
  description = <<-EOT
    The trailing part of the `sub` claim patterns this role accepts. The
    module prepends the repository-anchored prefix, so these are ONLY the part
    after it:

      production: ["ref:refs/heads/main"]
      staging:    ["*"]
      a tag:      ["ref:refs/tags/v1.2.3"]
      an env:     ["environment:prod"]

    Matched with StringLike, so * and ? are wildcards and a pattern with
    neither behaves as an exact match.

    Do not pass a whole "repo:..." claim here — the prefix is built for you,
    and the validation below rejects it rather than silently producing
    "repo:owner@1/name@2:repo:owner/name:ref:...", which matches nothing.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.subject_suffixes) > 0
    error_message = "subject_suffixes must contain at least one pattern. An empty list produces a StringLike condition with no values, which no token can satisfy."
  }

  validation {
    condition     = alltrue([for suffix in var.subject_suffixes : length(trimspace(suffix)) > 0])
    error_message = "subject_suffixes entries must not be empty or whitespace. An empty suffix yields a claim ending in \":\", which matches no token — say \"*\" if you mean any ref."
  }

  validation {
    condition     = alltrue([for suffix in var.subject_suffixes : !startswith(suffix, "repo:")])
    error_message = "subject_suffixes entries must not start with \"repo:\" — pass only the part after the repository prefix (e.g. \"ref:refs/heads/main\"), which this module builds from github_repo, github_owner_id and github_repo_id."
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

    Worth knowing what a boundary does not do: it bounds what this principal
    may do, and says nothing about who the principal is. That half is the
    trust policy, which is why subject_suffixes is anchored by construction.
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
