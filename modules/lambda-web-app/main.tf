locals {
  # Default ARN for AWS Lambda Web Adapter's own published layer (zip-package
  # deployments) — 753240598075 is the AWS Lambda Web Adapter project's
  # publishing account, a fixed public constant, NOT your account or
  # anything account-specific. Already overridable per-call via
  # var.lambda_web_adapter_layer_arn if you ever need a different layer
  # (e.g. your own copy published into your own account).
  # Verify this default is still current before applying:
  # https://github.com/awslabs/aws-lambda-web-adapter/releases
  lambda_web_adapter_layer_arn = coalesce(
    var.lambda_web_adapter_layer_arn,
    "arn:aws:lambda:${var.aws_region}:753240598075:layer:LambdaAdapterLayer${var.lambda_architecture == "arm64" ? "Arm64" : "X86"}:28",
  )
}

locals {
  # Hashed independently of the zip artifact itself (see zip_lambda below) so
  # this is computable at plan time even before the zip exists on a fresh apply.
  source_files = sort(fileset(var.source_dir, "**"))
  source_hash = sha256(join("", [
    for f in local.source_files : filesha256("${var.source_dir}/${f}")
  ]))
  output_zip = "${var.source_dir}.zip"
}

# Builds the deployment zip via a helper script instead of archive_file --
# see scripts/zip_lambda.py for why: archive_file can't produce a zip with
# run.sh's executable bit set when terraform apply runs on Windows.
resource "terraform_data" "lambda_zip" {
  triggers_replace = {
    source_hash = local.source_hash
  }

  provisioner "local-exec" {
    # Unquoted path.module is safe -- it's always a Terraform-generated
    # .terraform/modules/... path with no spaces. var.source_dir and the
    # output path go through env vars instead of argv (see scripts/zip_lambda.py
    # for why), so they're safe even if they do contain spaces.
    command = "python3 ${path.module}/scripts/zip_lambda.py"
    environment = {
      ZIP_SOURCE_DIR  = var.source_dir
      ZIP_OUTPUT_PATH = local.output_zip
    }
  }

  # These guard a SILENT failure, not a loud one. fileset() returns an empty
  # set for a directory that doesn't exist rather than erroring (verified
  # against this Terraform version), so without these an unbuilt source_dir
  # sails through plan, hands os.walk a missing path, and ships a perfectly
  # valid EMPTY zip to Lambda -- apply reports success and the function is
  # broken only at runtime. The pre-v1.1.0 archive_file implementation failed
  # loudly here ("could not archive missing directory"); restore that.
  lifecycle {
    precondition {
      condition     = length(local.source_files) > 0
      error_message = "source_dir (${var.source_dir}) is empty or does not exist. Run your project's Lambda build step (e.g. `npm run build:lambda`) before `terraform apply` -- this module zips the artifact, it does not build it."
    }

    precondition {
      condition     = contains(local.source_files, "run.sh")
      error_message = "source_dir (${var.source_dir}) contains no run.sh at its root. The Lambda Web Adapter's zip-package handler execs run.sh directly, so the artifact must include one (e.g. `#!/bin/sh` then `exec node src/index.js`)."
    }
  }
}

# Read-only: these SecureString parameters (Standard tier — free, unlike
# Secrets Manager) are the system of record and must already exist. Terraform
# deliberately does not manage or write their value — only reading it here
# means the secret's only durable home is SSM, never a local tfvars file or
# Terraform state as the source of truth.
#
# This resolves at APPLY time and the value is baked into the function's
# environment below. There is no runtime lookup, which is the deliberate trade
# — a deployed function has no runtime dependency on SSM — and it is also the
# thing that surprises people. Rotating one of these parameters changes nothing
# that is already running, with no error and no warning, until every consuming
# environment is applied again. README.md has the rotation procedure and a way
# to tell which deployments are behind.
data "aws_ssm_parameter" "secrets" {
  for_each        = var.ssm_secret_env_vars
  name            = each.value
  with_decryption = true
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.app_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach any resource-specific permissions (e.g. DynamoDB access) to
# aws_iam_role.lambda_exec.name from the root config — this module only ever
# grants the basic execution role, on purpose, so it stays agnostic of what
# the app actually talks to.

# Declared explicitly rather than left to Lambda. If this resource doesn't
# exist, Lambda creates /aws/lambda/<name> itself on first invocation, with
# two consequences that both cut against a repo whose premise is $0:
#
#   1. An auto-created group's retention is "Never Expire". Log storage then
#      accrues forever, and CloudWatch Logs' free tier (5GB) is not a cap —
#      it's the point where billing starts.
#   2. An auto-created group isn't in Terraform state, so `terraform destroy`
#      leaves it behind. It survives every teardown, indefinitely.
#
# BREAKING for any environment deployed before this resource existed: the
# auto-created group already exists, and the next apply fails with
# ResourceAlreadyExistsException. Import it once, then apply:
#
#     terraform import 'module.<name>.aws_cloudwatch_log_group.lambda' '/aws/lambda/<app_name>'
#
# See this repo's CHANGELOG.md for the full note.
resource "aws_cloudwatch_log_group" "lambda" {
  # Lambda writes to this exact name — it is derived from the function name,
  # not configurable on the function side.
  name              = "/aws/lambda/${var.app_name}"
  retention_in_days = var.retention_in_days
}

resource "aws_lambda_function" "app" {
  function_name = var.app_name
  role          = aws_iam_role.lambda_exec.arn

  runtime       = var.runtime
  handler       = "run.sh"
  architectures = [var.lambda_architecture]
  layers        = [local.lambda_web_adapter_layer_arn]

  filename         = local.output_zip
  source_code_hash = base64sha256(local.source_hash)

  # The log group dependency is about ordering in both directions. On create it
  # guarantees the group (with its retention) exists before the function can be
  # invoked and auto-create an un-managed one. On destroy Terraform reverses the
  # edge, tearing the function down first — without it, deleting the log group
  # while a live function still holds logs:CreateLogGroup (which
  # AWSLambdaBasicExecutionRole grants) just invites the next invocation to
  # recreate it, un-managed and back to Never Expire.
  depends_on = [terraform_data.lambda_zip, aws_cloudwatch_log_group.lambda]

  memory_size = var.memory_size
  timeout     = var.timeout

  environment {
    variables = merge(
      var.environment_variables,
      { for env_name, param in data.aws_ssm_parameter.secrets : env_name => param.value },
      {
        AWS_LAMBDA_EXEC_WRAPPER      = "/opt/bootstrap"
        AWS_LWA_PORT                 = var.port
        AWS_LWA_READINESS_CHECK_PATH = var.health_check_path
        PORT                         = var.port
        NODE_ENV                     = "production"
        TRUST_PROXY                  = "true"
        # Do not set AWS_REGION here — it's a Lambda-reserved env var.
      }
    )
  }
}

resource "aws_lambda_function_url" "app" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"
}

# authorization_type = "NONE" above only tells AWS not to require IAM SigV4
# signing on requests — it does NOT by itself grant permission to invoke the
# URL. Without these two resource-based policy statements, every request
# gets a generic 403 Forbidden before it ever reaches the function. As of
# October 2025, AWS requires BOTH statements below for public function URLs
# (previously InvokeFunctionUrl alone was enough) — see
# https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html
resource "aws_lambda_permission" "function_url_public" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "function_invoke_via_url" {
  statement_id             = "AllowPublicFunctionInvokeViaUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.app.function_name
  principal                = "*"
  invoked_via_function_url = true
}
