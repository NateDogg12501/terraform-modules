# github-oidc-deploy-role

An IAM role that GitHub Actions assumes over OIDC to deploy **one repository,
one environment** — no long-lived AWS access keys anywhere.

This is a **prerequisite** module: CI cannot deploy until the role exists.
It consumes the account's OIDC provider ARN from
[`github-oidc-provider`](../github-oidc-provider) and knows nothing else about
it.

Requires **Terraform >= 1.9** (the rest of this repo asks for >= 1.5) — see
[Why >= 1.9](#why--19) below, which is a security point, not a packaging one.

## Usage

One role per repo per environment. Production pins to `main`; staging accepts
any ref in the same repository:

```hcl
data "aws_iam_policy_document" "deploy" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:UpdateFunctionCode", "lambda:GetFunction"]
    resources = ["arn:aws:lambda:us-east-1:123456789012:function:kids-ledger-*"]
  }
}

module "prod_deploy_role" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/github-oidc-deploy-role?ref=v2.2.0"

  role_name         = "kids-ledger-prod-deploy"
  oidc_provider_arn = module.github_oidc.provider_arn
  github_repo       = "NateDogg12501/kids-ledger"

  # Only a run on main gets these credentials. Enforced by AWS.
  subject_claims = ["repo:NateDogg12501/kids-ledger:ref:refs/heads/main"]

  permissions_boundary_arn = aws_iam_policy.project_deploy_boundary.arn
  policy_json              = data.aws_iam_policy_document.deploy.json
}

module "staging_deploy_role" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/github-oidc-deploy-role?ref=v2.2.0"

  role_name         = "kids-ledger-staging-deploy"
  oidc_provider_arn = module.github_oidc.provider_arn
  github_repo       = "NateDogg12501/kids-ledger"

  # Any ref in this repo, including pull requests — see the caution below.
  subject_claims = ["repo:NateDogg12501/kids-ledger:*"]

  permissions_boundary_arn = aws_iam_policy.project_deploy_boundary.arn
  policy_json              = data.aws_iam_policy_document.staging_deploy.json
}
```

The consuming workflow needs `id-token: write` and the role ARN — no secrets:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789012:role/project-deploy/kids-ledger-prod-deploy
      aws-region: us-east-1
```

## The trust policy is the security boundary

Two conditions, and both matter:

| Condition | Test | Why |
|---|---|---|
| `token.actions.githubusercontent.com:aud` = `sts.amazonaws.com` | `StringEquals` | Exact, never `StringLike` — there is no legitimate wildcard audience. |
| `token.actions.githubusercontent.com:sub` matches `subject_claims` | `StringLike` | Staging legitimately needs a `*`; a pattern with no wildcard still matches exactly. |

The `sub` claim carries the repository *and* what in it is running:

```
repo:<owner>/<name>:ref:refs/heads/main    a run on the main branch
repo:<owner>/<name>:ref:refs/tags/v1.2.3   a run on a tag
repo:<owner>/<name>:pull_request           a pull_request-event run
repo:<owner>/<name>:environment:prod       a run in a named GitHub environment
```

**Pinning production to `...:ref:refs/heads/main` is the "only main deploys to
production" guarantee.** It holds because AWS refuses the `AssumeRole` call, not
because a workflow file says so — and a workflow file is editable in any pull
request, by anyone who can open one.

### The failure this module is built to prevent

A wildcard in the wrong position makes the role assumable by *any* repository
on GitHub, including one an attacker creates in the next five minutes.
`repo:*` and `repo:*:ref:refs/heads/main` both do this, and neither looks
alarming in the console.

So every `subject_claims` entry is validated to start with
`repo:<github_repo>:`, and `github_repo` itself is validated to contain no
wildcard (otherwise the first check would validate against a wildcard and prove
nothing). The trailing colon is what makes the prefix exact —
`repo:owner/name-evil:*` does not start with `repo:owner/name:`.

Passing a claim scoped to a different repository fails the **plan**, so it can
never reach an apply:

```
Error: Invalid value for variable

  on main.tf line 22, in module "bad":
  22:   subject_claims = ["repo:*"]
    ├────────────────
    │ var.github_repo is "NateDogg12501/kids-ledger"
    │ var.subject_claims is list of string with 1 element

Every subject_claims entry must start with "repo:NateDogg12501/kids-ledger:"
— a pattern not anchored to this repository would let other repositories
assume this role.
```

A near miss fails the same way: `repo:NateDogg12501/kids-ledger-evil:*` is
rejected, because the required prefix includes the trailing colon. So does a
wildcard `github_repo`, on its own rule.

(Worth knowing: this is a `plan`-time check, not a `terraform validate` one.
Validate does not evaluate a child module's variable validations, so a
consuming project's `validate` job will pass on a config this rejects. Plan
always runs before apply, so the guard still holds — but don't read a green
`validate` as having checked it.)

### Caution: what `repo:owner/name:*` really allows

The staging pattern accepts every ref and event in the repository, so anyone
who can push a branch or open a pull request against it can get staging
credentials. That is the intended trade-off for a staging environment in a
repo you control, and it is the reason production must not use the same
pattern. If you want something tighter than `*` but looser than one branch,
`repo:<owner>/<name>:environment:<name>` combined with GitHub's environment
protection rules is the usual next step.

Note also that the claim is case-sensitive on both sides: GitHub emits the
repository's canonical casing, and IAM condition matching does not fold case.

## `permissions_boundary_arn` is required

No default, deliberately. A boundary caps the role's effective permissions to
the intersection of the boundary and whatever is attached, so it still holds if
`policy_json` over-grants, or if something later attaches an extra policy out
of band.

These roles are created by an automated provisioner, which is precisely the
situation where an optional security argument gets omitted once and nobody
notices. Required means the plan fails; optional would mean an unbounded deploy
role that looks exactly like a bounded one.

**This module does not create the boundary policy.** That is account-scoped —
one boundary shared by every deploy role — and belongs in the account bootstrap
config alongside `github-oidc-provider`. This module only consumes its ARN.

## Why >= 1.9

Terraform 1.9 is the first release whose variable `validation` blocks can
reference *other* variables. Checking `subject_claims` against `github_repo` is
exactly that kind of cross-variable check, and it is the guard that keeps this
role from being assumable by an unrelated repository. On 1.8 the check could
not be written at all, so the version constraint fails loudly rather than
leaving the guard quietly absent.

Generated projects already require >= 1.10 for the S3 backend's native
locking, so in practice this costs nothing.

## Cost

**No `cost_acknowledged` flag, deliberately.** IAM roles, inline policies and
role assumptions are free; there is no billable configuration here for a gate
to catch. The [`cost_acknowledged` standard](../../README.md#adding-a-module)
covers modules that can provision something billable.

What this role *deploys* may of course cost money — that is gated in the
modules that create those resources (`dynamodb-single-table`, `s3-bucket`),
where the numbers are actually visible.

## What it doesn't manage

One role, one inline policy. No managed policy attachments (attach them from
the caller with `role_name` if you need one), no boundary policy, no OIDC
provider, no GitHub-side configuration — the repository still needs
`permissions: id-token: write` in its workflow, which no Terraform can set for
it.
