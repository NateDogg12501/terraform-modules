# A deploy role for one repository and one environment, assumable only by a
# GitHub Actions run whose OIDC token matches subject_claims.
#
# This module provisions no billable resources — IAM roles and policies are
# free — so it deliberately has no cost_acknowledged flag. What it deploys may
# well cost money; that is gated by the modules that create those resources.

locals {
  # The condition-key prefix is the provider's issuer host. Hardcoded to match
  # github-oidc-provider's url, since the trust policy is only correct if the
  # two agree.
  oidc_host = "token.actions.githubusercontent.com"
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

    # `sub` identifies the repository AND what in it is running:
    #   repo:<owner>/<name>:ref:refs/heads/main   a run on the main branch
    #   repo:<owner>/<name>:pull_request          a pull_request-event run
    #   repo:<owner>/<name>:environment:prod      a run in a named environment
    #
    # StringLike because staging legitimately passes a wildcard
    # ("repo:owner/name:*"). A pattern containing neither * nor ? matches
    # exactly under StringLike, so the production pin
    # "repo:owner/name:ref:refs/heads/main" is as tight here as StringEquals
    # would be — and it is what makes "only main deploys to production" a fact
    # AWS enforces, not a promise made by workflow YAML that any PR can edit.
    #
    # var.subject_claims is validated to be anchored to var.github_repo before
    # it can reach this line; see variables.tf.
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = var.subject_claims
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
