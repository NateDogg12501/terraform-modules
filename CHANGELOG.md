# Changelog

Consumers pin this repo by tag, so nothing here reaches a project until that
project bumps its `?ref=` and runs `terraform init -upgrade`. This file exists
so you can tell what a bump would actually pull in — and, more to the point,
so a fix cut here doesn't sit unnoticed downstream the way `v1.1.0` did (see
the note under that version).

Versions follow semver *from the consumer's point of view*: MAJOR means an
existing deployment cannot move onto this version by bumping the tag alone.

## v3.0.0 — 2026-08-10

**`github-oidc-deploy-role` only.** Every other module is untouched, but the tag
moves for the whole repo and a consumer pins one tag across its config, so
bumping to v3.0.0 means re-pinning every `?ref=` and editing any
`github-oidc-deploy-role` block.

**Why this is not optional.** Every role built by v2.x is unassumable. GitHub's
OIDC subject claim embeds numeric owner and repository IDs:

```
repo:NateDogg12501@28988424/aws-account@1329306836:ref:refs/heads/main
```

not the `repo:<owner>/<name>:...` form v2.x built its trust policies against and
that most documentation still shows. Nothing matches, and the only symptom is
`Not authorized to perform sts:AssumeRoleWithWebIdentity`, which says nothing
about the subject. This was found the first time a real workflow tried to
assume a role — v2.2.0 shipped having never been exercised end to end.

Note the API will not tell you: `GET
/repos/{owner}/{repo}/actions/oidc/customization/sub` reports
`use_immutable_subject: false` while the tokens it mints carry the IDs anyway.
Only a real token is authoritative.

### Changed (breaking)

- **`subject_claims` is replaced by `subject_suffixes`.** The caller now
  supplies only the part *after* the repository prefix — `"ref:refs/heads/main"`
  rather than `"repo:owner/name:ref:refs/heads/main"` — and the module builds
  the anchored prefix from `github_repo` and the two new ID variables.

  This is the same guard by a better mechanism. v2.x accepted whole `sub`
  patterns and *validated* that each was anchored to `github_repo`; v3.0.0
  *constructs* the anchor, so there is no value of `subject_suffixes` that
  escapes it. The distinction is the whole lesson of this release: a validation
  is only as correct as the format it was written against, and it stopped being
  correct silently. A construction fails loudly and completely instead.

- **`github_owner_id` and `github_repo_id` are new and required.** Both are
  numbers; get them with
  `gh api repos/<owner>/<name> --jq '{owner: .owner.id, repo: .id}'`.

- **`required_version` relaxed from `>= 1.9` to `>= 1.5`**, matching the rest of
  the repo. The 1.9 floor existed for a cross-variable `validation`, which no
  longer exists.

### Added

- **`subject_claims` output** — the fully-qualified patterns the trust policy
  actually accepts. When an assumption is refused, comparing this against a real
  token's `sub` is the fastest way to find out why.

### Migration

For each `github-oidc-deploy-role` block: add `github_owner_id` and
`github_repo_id`, then replace

```hcl
subject_claims = ["repo:NateDogg12501/kids-ledger:ref:refs/heads/main"]
```

with

```hcl
subject_suffixes = ["ref:refs/heads/main"]
```

Dropping the prefix is the whole edit; `["repo:owner/name:*"]` becomes
`["*"]`. Passing a full claim is rejected at plan time rather than silently
double-prefixed.

Applying produces an in-place `assume_role_policy` update on each role. No role
is replaced, and no role that worked before stops working — none of them worked.

## v2.2.0 — 2026-08-09

Nothing here changes an existing module, so a consumer on v2.1.0 can bump
`?ref=` with no migration step. Both new modules are additive, and both are
free (IAM only — no `cost_acknowledged` flag, deliberately; each README says
so).

### Added

- `github-oidc-provider`: the account-level `aws_iam_openid_connect_provider`
  for `token.actions.githubusercontent.com`, so GitHub Actions can deploy with
  short-lived STS credentials instead of long-lived AWS access keys.

  `thumbprint_list` is deliberately **unset**. AWS validates that endpoint
  against its own trusted root CA store and no longer uses the thumbprint, so
  pinning one of the constants still floating around the internet
  (`6938fd4d...`) buys nothing and breaks the day GitHub rotates a
  certificate. Reasoning is in `main.tf` and `docs/decisions.md` so the
  omission can't be mistaken for an oversight.

  **One per AWS account.** IAM permits a single provider per issuer URL, so a
  second apply in the same account fails with `EntityAlreadyExists`. The README
  covers adopting an existing one with `terraform import`, and the
  `data "aws_iam_openid_connect_provider"` alternative when another config
  should keep owning it.

- `github-oidc-deploy-role`: a deploy role for one repo and one environment,
  assumable only by a GitHub Actions run whose OIDC token matches the
  `subject_claims` it was created with.

  The trust policy pins `...:aud` to `sts.amazonaws.com` with `StringEquals`
  and matches `...:sub` against `subject_claims` with `StringLike`. Passing
  `["repo:<owner>/<name>:ref:refs/heads/main"]` is what makes "only `main`
  deploys to production" a rule **AWS** enforces, rather than one a workflow
  file promises — and a workflow file is editable in any pull request.

  Two guards, both failing the plan: every `subject_claims` entry must start
  with `repo:<github_repo>:`, and `github_repo` itself must contain no
  wildcard. Without the pair, a stray `repo:*` produces a role assumable by
  every repository on GitHub that looks entirely ordinary in the console. Note
  these are variable validations, which `terraform validate` does not evaluate
  for a child module — they fire at plan, which always precedes apply.

  `permissions_boundary_arn` is **required, with no default**, because these
  roles get created by an automated provisioner and an optional security
  argument is one that eventually gets left out silently. The module consumes
  the boundary; it does not create it (account-scoped, belongs in the account
  bootstrap config).

  Requires **Terraform >= 1.9**, unlike the rest of this repo's `>= 1.5`: 1.9
  is the first version whose variable validation can reference another
  variable, which the `subject_claims`-against-`github_repo` check needs.
  Generated projects already require >= 1.10 for the S3 backend's native
  locking.

- `docs/decisions.md` in this repo, recording the thumbprint decision, the
  required-boundary decision, and the validation/version-constraint decision.
  `project-template`'s `STANDARDS.md` asks every generated project to keep one;
  this repo now holds itself to the same rule.

- `README.md`: an **application vs prerequisite modules** section. The OIDC
  modules are the first of a new category — things that must exist before CI
  can deploy at all, that outlive every project in the account, and that a
  project's `terraform destroy` must not take with it.

## v2.1.0 — 2026-08-08

### Added

- `s3-bucket`: a new general-purpose S3 bucket module. Motivating use case:
  backing a project's own Terraform state, but nothing in it is
  state-specific.

  AWS's S3 Free Tier stopped expiring after 12 months in mid-2024 — it's now
  perpetual for new and existing accounts (5GB S3 Standard storage, 20,000
  GET, 2,000 PUT/COPY/POST/LIST per month), which is what makes an S3 module
  fit this repo's Always Free standard at all.

  Defaults: SSE-S3 encryption (`AES256`, no KMS cost), `BucketOwnerEnforced`
  ownership (ACLs off entirely), public access fully blocked, a bucket policy
  denying any request over plain HTTP, and a lifecycle rule expiring
  noncurrent object versions after 90 days so a bucket that's overwritten a
  lot (e.g. state, applied on every run) doesn't quietly outgrow the 5GB
  allowance.

  Same `cost_acknowledged` + `lifecycle` precondition pattern as
  `dynamodb-single-table`, gating `sse_algorithm = "aws:kms"` — but see the
  module's README for what that gate *can't* catch: S3's Always Free limits
  are usage-based (GB stored, requests made), not configuration-based, so no
  plan-time precondition can see them the way the DynamoDB capacity gate can.

  README documents both the native-locking backend config (`use_lockfile`,
  Terraform >= 1.10) and the `dynamodb-single-table`-backed alternative for
  older Terraform.

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
