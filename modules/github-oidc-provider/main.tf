# The account-level trust anchor for GitHub Actions. Created ONCE per AWS
# account: IAM allows only one OIDC provider per issuer URL, so a second
# `terraform apply` of this module in the same account fails with
# EntityAlreadyExists. See the README for how to adopt an existing one.
#
# This module provisions no billable resources — an IAM OIDC provider is free —
# so it deliberately has no cost_acknowledged flag.
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # The audience GitHub puts in the token's `aud` claim when a workflow calls
  # the OIDC endpoint with the default audience, which is what
  # aws-actions/configure-aws-credentials requests. Hardcoded rather than a
  # variable: a role's trust policy also pins `...:aud = sts.amazonaws.com`,
  # and the two have to agree for anything to work. Making it configurable
  # would only create a way for them to disagree.
  client_id_list = ["sts.amazonaws.com"]

  # Deliberately unset (var.thumbprint_list defaults to null, which Terraform
  # treats as "argument omitted").
  #
  # Thumbprint pinning was originally how IAM verified the IdP's TLS
  # certificate, which meant every consumer hardcoded a GitHub leaf/intermediate
  # thumbprint and every consumer broke when GitHub rotated it — that is the
  # origin of the well-known 6938fd4d... and 1c58a3a8... constants still copied
  # around the internet. In July 2023 AWS moved to validating
  # token.actions.githubusercontent.com against its own trusted root CA store,
  # so the value is no longer used for this endpoint. The argument still exists
  # on the resource (and AWS still stores and returns something), which is why
  # an omission needs this comment: it is a decision, not an oversight.
  #
  # Recorded in docs/decisions.md. The variable stays as an escape hatch in case
  # that ever changes; nothing should need it today.
  thumbprint_list = var.thumbprint_list

  tags = var.tags
}
