# github-oidc-deploy-role

An IAM role that GitHub Actions assumes over OIDC to deploy **one repository,
one environment** — no long-lived AWS access keys anywhere.

This is a **prerequisite** module: CI cannot deploy until the role exists.
It consumes the account's OIDC provider ARN from
[`github-oidc-provider`](../github-oidc-provider) and knows nothing else about
it.

Requires **Terraform >= 1.5**, the same as the rest of this repo — see
[Terraform version](#terraform-version), which changed in v3.0.0.

## The `sub` claim contains numeric IDs — read this first

GitHub's OIDC subject claim is **not** the `repo:<owner>/<name>:...` form that
most documentation still shows. It is:

```
repo:NateDogg12501@28988424/kids-ledger@1329306836:ref:refs/heads/main
     └── owner ──┘└ owner id ┘└── name ──┘└ repo id ┘
```

A trust policy written against the documented form matches no token GitHub will
ever mint, and the only symptom is:

```
Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

which says nothing about the subject. **This module takes the IDs and builds
the claim for you**, so the mistake is not available to make.

**Do not try to read the format off the API.** `GET
/repos/{owner}/{repo}/actions/oidc/customization/sub` reports
`use_immutable_subject: false` while the tokens it mints carry the IDs anyway.
Only a real token is authoritative. To read one, in a job with
`id-token: write`:

```bash
curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com"
```

then base64-decode the payload (the middle dot-separated segment). Print only
the claims you need, never the whole token.

Get the two IDs with:

```bash
gh api repos/NateDogg12501/kids-ledger --jq '{owner: .owner.id, repo: .id}'
```

## Usage

One role per repo per environment. Production pins to `main`; staging accepts
any ref in the same repository. `subject_suffixes` is only the part *after* the
repository prefix — the module anchors it:

```hcl
data "aws_iam_policy_document" "deploy" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:UpdateFunctionCode", "lambda:GetFunction"]
    resources = ["arn:aws:lambda:us-east-1:123456789012:function:kids-ledger-*"]
  }
}

module "prod_deploy_role" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/github-oidc-deploy-role?ref=v3.0.0"

  role_name         = "kids-ledger-prod-deploy"
  oidc_provider_arn = module.github_oidc.provider_arn
  github_repo       = "NateDogg12501/kids-ledger"
  github_owner_id   = 28988424
  github_repo_id    = 1329306836

  # Only a run on main gets these credentials. Enforced by AWS.
  subject_suffixes = ["ref:refs/heads/main"]

  permissions_boundary_arn = aws_iam_policy.project_deploy_boundary.arn
  policy_json              = data.aws_iam_policy_document.deploy.json
}

module "staging_deploy_role" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/github-oidc-deploy-role?ref=v3.0.0"

  role_name         = "kids-ledger-staging-deploy"
  oidc_provider_arn = module.github_oidc.provider_arn
  github_repo       = "NateDogg12501/kids-ledger"
  github_owner_id   = 28988424
  github_repo_id    = 1329306836

  # Any ref in this repo, including pull requests — see the caution below.
  subject_suffixes = ["*"]

  permissions_boundary_arn = aws_iam_policy.project_deploy_boundary.arn
  policy_json              = data.aws_iam_policy_document.staging_deploy.json
}
```

The `subject_claims` output shows exactly what was built, which is the first
thing to compare against a real token when an assumption is refused.

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
| `token.actions.githubusercontent.com:sub` matches the built claims | `StringLike` | Staging legitimately needs a `*`; a pattern with no wildcard still matches exactly. |

The `sub` claim carries the repository *and* what in it is running. The prefix
is fixed by the module; `subject_suffixes` chooses the tail:

```
ref:refs/heads/main    a run on the main branch
ref:refs/tags/v1.2.3   a run on a tag
pull_request           a pull_request-event run
environment:prod       a run in a named GitHub environment
*                      any ref or event in this repository
```

**Pinning production to `ref:refs/heads/main` is the "only main deploys to
production" guarantee.** It holds because AWS refuses the `AssumeRole` call, not
because a workflow file says so — and a workflow file is editable in any pull
request, by anyone who can open one.

### The failure this module is built to prevent

A wildcard in the wrong position makes the role assumable by *any* repository
on GitHub, including one an attacker creates in the next five minutes.
`repo:*` and `repo:*:ref:refs/heads/main` both do this, and neither looks
alarming in the console.

**As of v3.0.0 that is prevented by construction rather than by validation.**
The caller no longer supplies a whole `sub` pattern; it supplies only the part
after the prefix, and the module builds
`repo:<owner>@<owner_id>/<name>@<repo_id>:` from `github_repo`,
`github_owner_id` and `github_repo_id`. There is no value of
`subject_suffixes` that escapes that prefix, so an unanchored claim is not
expressible.

That change was forced by the claim-format change, and the reason it is the
better design is exactly why the old one failed: a validation is only as
correct as the format it was written against, and it silently stopped being
correct when GitHub added the IDs. A construction cannot go stale in the same
way — if the prefix is wrong, *nothing* works loudly and immediately, rather
than one guard quietly not guarding.

Two validations remain, both catching caller mistakes rather than attacks:
`github_repo` must contain no wildcard (it widens the prefix), and a
`subject_suffixes` entry must not itself start with `repo:` — pasting a whole
claim would otherwise produce
`repo:owner@1/name@2:repo:owner/name:ref:refs/heads/main`, which matches
nothing.

(Worth knowing: variable validation is a `plan`-time check, not a
`terraform validate` one. Validate does not evaluate a child module's variable
validations, so a consuming project's `validate` job will pass on a config this
rejects. Plan always runs before apply, so the guard still holds — but don't
read a green `validate` as having checked it.)

### Caution: what `subject_suffixes = ["*"]` really allows

The staging pattern accepts every ref and event in the repository, so anyone
who can push a branch or open a pull request against it can get staging
credentials. That is the intended trade-off for a staging environment in a
repo you control, and it is the reason production must not use the same
pattern. If you want something tighter than `*` but looser than one branch,
`subject_suffixes = ["environment:<name>"]` combined with GitHub's environment
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

## Terraform version

`>= 1.5`, the same as the rest of this repo.

Through v2.x this module asked for `>= 1.9`, because Terraform 1.9 is the first
release whose variable `validation` blocks may reference *other* variables, and
the anchoring guard was a validation of `subject_claims` against `github_repo`.
v3.0.0 replaced that check with a construction — the prefix is built from
`github_repo` and the two IDs, so nothing cross-references anything — and the
constraint went with the reason for it. Kept in `docs/decisions.md` rather than
here, since it no longer describes anything true.

Generated projects require `>= 1.10` for the S3 backend's native locking
regardless, so nothing downstream notices either number.

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
