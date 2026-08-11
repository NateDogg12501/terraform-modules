# A deploy role for one repository and one environment, assumable only by a
# GitHub Actions run whose OIDC token matches the subject this module builds.
#
# This module provisions no billable resources — IAM roles and policies are
# free — so it deliberately has no cost_acknowledged flag. What it deploys may
# well cost money; that is gated by the modules that create those resources.

locals {
  # The condition-key prefix is the provider's issuer host. Hardcoded to match
  # github-oidc-provider's url, since the trust policy is only correct if the
  # two agree.
  oidc_host = "token.actions.githubusercontent.com"

  github_owner = split("/", var.github_repo)[0]
  github_name  = split("/", var.github_repo)[1]

  # GitHub embeds the numeric owner and repository IDs in the `sub` claim:
  #
  #   repo:<owner>@<owner_id>/<name>@<repo_id>:ref:refs/heads/main
  #
  # not the `repo:<owner>/<name>:...` form that most documentation and every
  # blog post still shows. A trust policy written against the documented form
  # matches nothing, and the failure is an opaque
  # "Not authorized to perform sts:AssumeRoleWithWebIdentity" with no hint that
  # the subject is the problem. The IDs are what make the claim survive a
  # rename: a repository deleted and recreated under the same name gets a new
  # ID and therefore cannot inherit the old one's trust.
  #
  # Do not try to read the format off the API. GET
  # /repos/{owner}/{repo}/actions/oidc/customization/sub reports
  # `use_immutable_subject: false` while tokens still carry the IDs; only a
  # real token tells you the truth. To read one:
  #
  #   curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  #     "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com"
  #
  # then base64-decode the payload segment.
  subject_prefix = "repo:${local.github_owner}@${var.github_owner_id}/${local.github_name}@${var.github_repo_id}:"

  # The security guard, and note what changed in v3.0.0: it is now a
  # *construction*, not a *check*. Before, the caller passed whole `sub`
  # patterns and a validation rejected any that were not anchored to this
  # repository — which works only for as long as the validation is right, and
  # it stopped being right the moment the claim format changed. Building the
  # anchored prefix here means a caller cannot express an unanchored claim at
  # all: there is no value of subject_suffixes that escapes the prefix.
  subject_claims = [for suffix in var.subject_suffixes : "${local.subject_prefix}${suffix}"]
}

# The trust policy IS the security boundary. Everything below it (policy_json,
# the boundary) limits what an authorised caller can do; this decides who the
# authorised caller is.
data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "GitHubActionsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # `aud` is fixed and exact. GitHub sets it from the audience the workflow
    # requests, so without this an actor who can get a token minted for some
    # other audience has one fewer thing to get right. StringEquals, never
    # StringLike: there is no legitimate wildcard audience.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # `sub` identifies the repository AND what in it is running. With the
    # prefix built above, subject_suffixes supplies only the trailing part:
    #
    #   ref:refs/heads/main   a run on the main branch
    #   ref:refs/tags/v1.2.3  a run on a tag
    #   pull_request          a pull_request-event run
    #   environment:prod      a run in a named GitHub environment
    #   *                     any ref or event in this repository
    #
    # StringLike because staging legitimately passes "*". A pattern containing
    # neither * nor ? matches exactly under StringLike, so the production pin
    # is as tight here as StringEquals would be — and it is what makes "only
    # main deploys to production" a fact AWS enforces, not a promise made by
    # workflow YAML that any PR can edit.
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = local.subject_claims
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  path                 = var.iam_path
  description          = "GitHub Actions deploy role for ${var.github_repo}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration

  # Required by this module, with no default. A boundary caps the role's
  # effective permissions to the intersection of this policy and whatever is
  # attached — so it still holds if a later change over-grants policy_json, or
  # if something attaches an extra policy out of band.
  permissions_boundary = var.permissions_boundary_arn

  tags = var.tags
}

# Inline rather than a managed policy: it is meaningless without this role, and
# an inline policy is deleted with the role instead of being left behind. Also
# the larger of the two size limits (10,240 characters against a managed
# policy's 6,144).
resource "aws_iam_role_policy" "this" {
  name   = "${var.role_name}-permissions"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}
