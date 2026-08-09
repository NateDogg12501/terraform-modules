output "provider_arn" {
  description = "ARN of the GitHub OIDC provider. Pass to github-oidc-deploy-role's oidc_provider_arn."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "provider_url" {
  description = "Issuer URL this provider trusts, without the https:// scheme — the prefix used in a role's trust-policy condition keys (token.actions.githubusercontent.com:aud / :sub)."
  value       = aws_iam_openid_connect_provider.github.url
}
