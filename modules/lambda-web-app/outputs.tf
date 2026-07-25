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
