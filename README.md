# terraform-modules

Reusable Terraform modules for personal/demo projects hosted on AWS, kept
inside the Always Free tier. One repo, multiple module subdirectories —
not a repo per module. At this scale (a handful of small projects, not a
team), the per-repo-per-module convention larger orgs use is overhead with
no payoff; the `//subdir` git source syntax below gives the same
versioning (via tags) without the extra repos to maintain.

## Modules

- [`modules/lambda-web-app`](modules/lambda-web-app) — Node app on Lambda
  behind a public Function URL, via Lambda Web Adapter.
- [`modules/dynamodb-single-table`](modules/dynamodb-single-table) — a
  single DynamoDB table with arbitrary GSIs.

See each module's README for a usage example, and its comments for
gotchas worth knowing before you rely on it (public Function URL needing
two separate `aws_lambda_permission` statements, the AWS provider v6+
requirement, the `hash_key`-not-`key_schema` GSI workaround, SSM
`SecureString` instead of Secrets Manager for cost reasons).

**`terraform init` + `terraform validate` pass** for both modules, and the
whole chain has been exercised live: a project generated from
`project-template` successfully pulled both modules from this repo's
`v1.0.0` tag over `git::https://...`, resolved providers, and validated
clean. `lambda-web-app` has since been through a real `terraform apply`
against an AWS account (from `n8nDemo`) and the deployed Function URL was
verified serving traffic end to end.

## Versioning

Tag releases (`v1.0.0`, `v1.1.0`, ...) on this repo. Consumers pin a specific
tag in their `source` so a module change here doesn't silently ripple into
every project using it:

```hcl
module "app" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/lambda-web-app?ref=v1.2.0"
  # ...
}
```

Bump the tag (and re-run `terraform init -upgrade` in consuming projects)
when you're ready to pull in a change — not automatically.

## Adding a module

1. New directory under `modules/`, following the existing shape:
   `versions.tf` (required_providers only, no `provider` block — that's the
   root config's job), `variables.tf`, `main.tf`, `outputs.tf`, `README.md`
   with a usage example.
2. Keep modules single-purpose and composable — `lambda-web-app` doesn't
   know about DynamoDB, `dynamodb-single-table` doesn't know about Lambda;
   a root config wires them together and attaches whatever IAM permissions
   the pairing actually needs.
3. Tag a new version once it's used successfully by at least one real
   project.
