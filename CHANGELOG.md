# Changelog

Consumers pin this repo by tag, so nothing here reaches a project until that
project bumps its `?ref=` and runs `terraform init -upgrade`. This file exists
so you can tell what a bump would actually pull in — and, more to the point,
so a fix cut here doesn't sit unnoticed downstream the way `v1.1.0` did (see
the note under that version).

Versions follow semver *from the consumer's point of view*: MAJOR means an
existing deployment cannot move onto this version by bumping the tag alone.

## v2.0.0 — 2026-08-03

### Breaking: `lambda-web-app` now manages the CloudWatch log group

The module declares `aws_cloudwatch_log_group` for `/aws/lambda/<app_name>`.
Previously it never did, so Lambda auto-created that group on first invocation.

**Any environment already deployed on v1.x has such a group, and the first
apply on v2.0.0 will fail with `ResourceAlreadyExistsException`** — Terraform
tries to create a group AWS already has. Import it once, per deployment:

```bash
terraform import 'module.<module_name>.aws_cloudwatch_log_group.lambda' '/aws/lambda/<app_name>'
```

`<module_name>` is whatever you called the module block (`module "app"` →
`module.app`), and `<app_name>` is the `app_name` you passed it. A fresh
deployment that has never been applied needs nothing — there is no group yet.

After importing, expect the plan to show one in-place change: retention moving
from Never Expire to the new 14-day default. That is the point of the change,
but it does mean logs older than the retention you settle on will age out, so
pick `retention_in_days` before you apply if 14 days is wrong for you.

Why this is worth a breaking change at all:

- An auto-created group's retention is **Never Expire**. CloudWatch Logs' free
  tier (5GB) is not a cap, it is where billing starts — so log storage accrued
  forever against a repo whose whole premise is $0.
- An auto-created group is **not in Terraform state**, so `terraform destroy`
  never deleted it. It survived every teardown, and kept accruing.

### Breaking: `dynamodb-single-table` gates billable configurations

New `cost_acknowledged` (bool, default `false`). A `lifecycle` precondition
now fails the **plan** when the table's configuration leaves the AWS Always
Free tier and that flag is false:

- `billing_mode = "PAY_PER_REQUEST"` — on-demand is not covered by the free
  tier at all; it bills per request from the first one.
- Provisioned capacity summed over the table and all its GSIs exceeding
  25 RCU or 25 WCU.

The default configuration (`PROVISIONED`, 5/5, no GSIs) is inside the free
tier and never trips this, so most consumers see no change. To apply a
billable table deliberately: log the decision in your project's
`docs/decisions.md`, then set `cost_acknowledged = true`.

Note the limit of what a module can check: the 25 RCU/25 WCU allowance is
shared per account+region across every table in every project. Passing this
check means this table alone is inside the allowance, not that your account
still is.

### Added

- `lambda-web-app`: `retention_in_days` (default `14`), validated against
  CloudWatch's fixed set of accepted values so a number like `10` is rejected
  at plan time instead of by the API mid-apply. `0` means never expire.
- `lambda-web-app`: `log_group_name` output.
- `.github/workflows/ci.yml` — `terraform fmt -check -recursive` at the repo
  root, plus `init -backend=false` and `validate` for every directory under
  `modules/`. The pre-commit hook added in v1.2.0's range is local-only and
  `--no-verify` bypasses it; CI is the actual backstop. Modules are discovered
  at runtime, so a newly added one is covered without editing the workflow.
- This changelog, and the release checklist in `README.md`.

## v1.2.0 — 2026-08-02

- `lambda-web-app`: two `lifecycle` preconditions reject an unbuilt or
  `run.sh`-less `source_dir` at plan time.

  This restored a safety net that v1.1.0 had quietly removed. `archive_file`
  used to fail loudly on a missing directory (`could not archive missing
  directory`); the zip script that replaced it did not, and `fileset()`
  returns an *empty set* for a nonexistent directory rather than erroring. The
  combination meant forgetting the build step produced a valid, empty zip and
  an apply that reported success while deploying a Lambda with no code in it.

- Also in this range (untagged at the time): `.githooks/pre-commit`, refusing
  commits whose staged `.tf`/`.tfvars` files aren't `terraform fmt`-clean.
  Needs `git config core.hooksPath .githooks` once per clone.

## v1.1.0 — 2026-08-02

- `lambda-web-app`: build the deployment zip with `scripts/zip_lambda.py`
  instead of the `archive_file` data source, and drop the `archive` provider.

  `archive_file` mirrors whatever executable bit it reads from the host
  filesystem, and Windows has no such bit — so a zip built by `terraform
  apply` on Windows silently dropped `run.sh`'s `+x` and the Lambda failed to
  start. Confirmed lost 100% of the time on an actual Windows-built archive.
  The zip script sets the mode explicitly, so it is correct on any host OS.

**This is the fix that motivated this file.** It shipped, and then this repo's
own READMEs went on advertising `?ref=v1.0.0` in their usage examples — so
anyone copying the documented example kept pinning the broken version.
`idea-workflow-example-1`'s `docs/decisions.md` records this as *plausibly why
the template never picked the fix up*. Hence the release checklist in
`README.md`, whose first item is updating every advertised version string.

## v1.0.0 — 2026-07-25

Initial release: `lambda-web-app` (Node app on Lambda behind a public Function
URL via Lambda Web Adapter) and `dynamodb-single-table` (one table, arbitrary
GSIs).
