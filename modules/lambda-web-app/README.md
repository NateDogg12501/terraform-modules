# lambda-web-app

Deploys a Node app (via [Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter))
behind a public Lambda Function URL, staying inside AWS's Always Free tier:
Lambda's 1M free requests/month, no ALB, no API Gateway.

Gotchas worth knowing before you rely on it: public Function URLs need
**two** separate `aws_lambda_permission` statements (not one — see the
comments in `main.tf`), and this requires the AWS provider v6+.

`source_dir` must contain a `run.sh` (with a shebang, e.g. `#!/bin/sh\nexec
node server.js`) — the Lambda Web Adapter's zip-package handler execs it
directly. The module zips `source_dir` itself via `scripts/zip_lambda.py`
(needs `python3` on PATH at apply time) rather than the more common
`archive_file` data source, because `archive_file` mirrors whatever
executable bit it reads from the host filesystem — and on Windows there is
no such bit for it to read, so a zip built by `terraform apply` on Windows
silently drops `run.sh`'s +x, and the Lambda then fails to start. Confirmed
by an actual `archive_file` zip built on Windows: exec bit lost 100% of the
time. This module's zip script sets the mode explicitly instead, so it's
correct regardless of host OS.

Two resource preconditions reject an unbuilt `source_dir` at plan time. They
exist because `fileset()` returns an *empty set* for a directory that doesn't
exist rather than erroring — so without them, forgetting the build step
produced a valid but empty zip and an apply that reported success while
deploying a Lambda with no code in it. Swapping `archive_file` (which failed
loudly with `could not archive missing directory`) for the zip script quietly
removed that safety net; the preconditions put it back.

Deliberately does **not** manage a datastore or its IAM permissions — pair
with `dynamodb-single-table` (or nothing, if your app is stateless) and
attach any extra policies to `lambda_role_name` from your root config.

## Logs

The module declares the `/aws/lambda/<app_name>` log group itself, with
`retention_in_days` (default 14, `0` for never expire). Left to Lambda, that
group gets auto-created with retention **Never Expire** and — because it isn't
in Terraform state — survives `terraform destroy` and keeps accruing storage
against CloudWatch Logs' 5GB free tier forever.

**Upgrading a deployment that already exists on v1.x:** the auto-created group
is already there, so the first apply fails with
`ResourceAlreadyExistsException`. Import it once, then apply:

```bash
terraform import 'module.app.aws_cloudwatch_log_group.lambda' '/aws/lambda/my-app'
```

Substitute your own module block name for `app` and your `app_name` for
`my-app`. A deployment that has never been applied needs nothing. See
[`CHANGELOG.md`](../../CHANGELOG.md) for the full note — including that the
post-import plan will show retention changing away from Never Expire, which
ages out logs older than whatever you set.

## Usage

```hcl
module "app" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/lambda-web-app?ref=v2.0.0"

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
