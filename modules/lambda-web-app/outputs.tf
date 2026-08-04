output "lambda_function_url" {
  description = "Public URL of the running app"
  value       = aws_lambda_function_url.app.function_url
}

output "lambda_function_name" {
  value = aws_lambda_function.app.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.app.arn
}

output "lambda_role_name" {
  description = "Attach additional IAM policies (e.g. DynamoDB access) to this role from the root config"
  value       = aws_iam_role.lambda_exec.name
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_exec.arn
}

output "log_group_name" {
  description = "CloudWatch log group this function writes to — also the import ID if you are adopting a pre-existing auto-created group (see CHANGELOG.md)"
  value       = aws_cloudwatch_log_group.lambda.name
}
