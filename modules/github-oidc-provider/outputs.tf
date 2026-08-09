output "provider_arn" {
  description = "ARN of the GitHub OIDC provider. Pass to github-oidc-deploy-role's oidc_provider_arn."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "provider_url" {
  description = <<-EOT
    Issuer URL this provider trusts, WITH the scheme
    (https://token.actions.githubusercontent.com) — it is the `iss` claim, not
    a condition-key prefix. Trust-policy condition keys use the bare host:
    token.actions.githubusercontent.com:aud / :sub. Don't build one by
    interpolating this output, or you get an https:// in the key name and a
    condition that silently matches nothing.
  EOT
  value       = aws_iam_openid_connect_provider.github.url
}
