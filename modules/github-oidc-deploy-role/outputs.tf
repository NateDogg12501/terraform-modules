output "role_arn" {
  description = "ARN of the deploy role. This is what a workflow passes to aws-actions/configure-aws-credentials as role-to-assume."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the deploy role, for attaching further policies from the caller."
  value       = aws_iam_role.this.name
}

output "role_unique_id" {
  description = "The role's stable unique ID (AROA...). Unlike the ARN it is never reused, so it is what to match on in CloudTrail or in an aws:userId condition."
  value       = aws_iam_role.this.unique_id
}
