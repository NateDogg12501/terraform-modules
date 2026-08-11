output "role_arn" {
  description = "ARN of the deploy role. This is what a workflow passes to aws-actions/configure-aws-credentials as role-to-assume."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the deploy role, for attaching further policies from the caller."
  value       = aws_iam_role.this.name
}

output "subject_claims" {
  description = "The fully-qualified `sub` patterns this role's trust policy accepts, as built from github_repo, github_owner_id, github_repo_id and subject_suffixes. Exposed for debugging: when an assumption fails with \"Not authorized to perform sts:AssumeRoleWithWebIdentity\", comparing this against the token's real `sub` claim is the fastest way to find out why."
  value       = local.subject_claims
}

output "role_unique_id" {
  description = "The role's stable unique ID (AROA...). Unlike the ARN it is never reused, so it is what to match on in CloudTrail or in an aws:userId condition."
  value       = aws_iam_role.this.unique_id
}
