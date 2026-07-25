# lambda-web-app

Deploys a Node app (via [Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter))
behind a public Lambda Function URL, staying inside AWS's Always Free tier:
Lambda's 1M free requests/month, no ALB, no API Gateway.

Gotchas worth knowing before you rely on it: public Function URLs need
**two** separate `aws_lambda_permission` statements (not one — see the
comments in `main.tf`), and this requires the AWS provider v6+.

Deliberately does **not** manage a datastore or its IAM permissions — pair
with `dynamodb-single-table` (or nothing, if your app is stateless) and
attach any extra policies to `lambda_role_name` from your root config.

## Usage

```hcl
module "app" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/lambda-web-app?ref=v1.0.0"

  app_name   = "my-app"
  aws_region = var.aws_region
  source_dir = "${path.module}/../dist-lambda"

  ssm_secret_env_vars = {
    APP_PASSWORD   = "/my-app/app_password"
    SESSION_SECRET = "/my-app/session_secret"
  }

  environment_variables = {
    WEB_DIST = "/var/task/web"
  }
}

# Grant the Lambda whatever it actually needs to talk to — this module
# intentionally never assumes what that is.
resource "aws_iam_role_policy" "app_datastore_access" {
  name = "${var.app_name}-datastore-access"
  role = module.app.lambda_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
      Resource = [module.table.table_arn]
    }]
  })
}

output "url" {
  value = module.app.lambda_function_url
}
```

## Before `terraform apply`

1. Build your Lambda artifact into `source_dir` (this module zips it, it does not build it).
2. Create every SSM parameter named in `ssm_secret_env_vars`:
   ```bash
   aws ssm put-parameter --name "/my-app/app_password" --type SecureString --value "..."
   ```
