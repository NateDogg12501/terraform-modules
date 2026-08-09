# terraform-modules

Reusable Terraform modules for personal/demo projects hosted on AWS, kept
inside the Always Free tier. One repo, multiple module subdirectories —
not a repo per module. At this scale (a handful of small projects, not a
team), the per-repo-per-module convention larger orgs use is overhead with
no payoff; the `//subdir` git source syntax below gives the same
versioning (via tags) without the extra repos to maintain.

## Modules

Two kinds, and the difference is worth keeping straight — see
[Application vs prerequisite modules](#application-vs-prerequisite-modules).

**Application modules** — the things a project is made of:

- [`modules/lambda-web-app`](modules/lambda-web-app) — Node app on Lambda
  behind a public Function URL, via Lambda Web Adapter.
- [`modules/dynamodb-single-table`](modules/dynamodb-single-table) — a
  single DynamoDB table with arbitrary GSIs.
- [`modules/s3-bucket`](modules/s3-bucket) — a general-purpose S3 bucket,
  encrypted and locked down by default. Motivating use case: backing a
  project's own Terraform state.

**Prerequisite modules** — what has to exist before CI can deploy at all:

- [`modules/github-oidc-provider`](modules/github-oidc-provider) — the
  account-level trust anchor for GitHub Actions. One per AWS account.
- [`modules/github-oidc-deploy-role`](modules/github-oidc-deploy-role) — a
  deploy role for one repo and one environment, assumable over OIDC. Its
  trust policy is what makes "only `main` deploys to production" a rule AWS
  enforces rather than one a workflow file promises.

See each module's README for a usage example, and its comments for
gotchas worth knowing before you rely on it (public Function URL needing
two separate `aws_lambda_permission` statements, the AWS provider v6+
requirement, the `hash_key`-not-`key_schema` GSI workaround, SSM
`SecureString` instead of Secrets Manager for cost reasons, S3's Always Free
limits being usage-based rather than configuration-based, the OIDC provider
being one-per-account and failing with `EntityAlreadyExists` on a second).

**`terraform init` + `terraform validate` pass** for every module — checked
on every push by [CI](#ci) rather than asserted here — and the
whole chain has been exercised live: a project generated from
`project-template` successfully pulled `lambda-web-app` and
`dynamodb-single-table` from this repo's `v1.0.0` tag over
`git::https://...`, resolved providers, and validated clean. `lambda-web-app`
has since been through a real `terraform apply` against an AWS account (from
`n8nDemo`) and the deployed Function URL was verified serving traffic end to
end. `s3-bucket`, `github-oidc-provider` and `github-oidc-deploy-role` have not
yet been through a live `terraform apply` — CI covers `init`/`validate` only.

### Application vs prerequisite modules

The two OIDC modules are a different category from the other three, and naming
the difference is what keeps this repo from drifting into a junk drawer:

|  | Application | Prerequisite |
|---|---|---|
| What it is | Something a project is *made of* | Something that must exist *before* the project can be built or deployed |
| Consumed by | A project's `terraform/` root config | An account-level bootstrap config, usually applied once by hand |
| Lifecycle | Created and destroyed with the project | Outlives every project in the account |
| How many | One per project that needs it | `github-oidc-provider`: one per AWS account. `github-oidc-deploy-role`: one per repo per environment |
| Today | `lambda-web-app`, `dynamodb-single-table`, `s3-bucket` | `github-oidc-provider`, `github-oidc-deploy-role` |

The practical consequence: `terraform destroy` on a project must not take a
prerequisite with it. That is why the provider module documents adopting an
existing provider by `terraform import` rather than creating a second one, and
why neither OIDC module is wired into an application module.

Everything else in this README — module shape, pinning, the release checklist,
CI — applies identically to both.

## Versioning

Tag releases (`v1.0.0`, `v1.1.0`, ...) on this repo. Consumers pin a specific
tag in their `source` so a module change here doesn't silently ripple into
every project using it:

```hcl
module "app" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/lambda-web-app?ref=v2.2.0"
  # ...
}
```

Bump the tag (and re-run `terraform init -upgrade` in consuming projects)
when you're ready to pull in a change — not automatically.

[`CHANGELOG.md`](CHANGELOG.md) says what each tag actually contains, so you
can tell whether a bump is worth doing and whether it needs manual steps.
MAJOR here means *an existing deployment can't move onto it by bumping the
tag alone* — v2.0.0, for instance, needs a `terraform import` first.

### Release checklist

1. **Update every advertised version string.** They are maintained by hand,
   and a stale one is not cosmetic — it is the documented cause of a real
   bug persisting downstream (see `v1.1.0` in the changelog: the fix shipped,
   the READMEs kept advertising `v1.0.0`, and the projects copying those
   examples kept pinning the broken version). Find them all:

   ```bash
   grep -rn "ref=v" --include="*.md" .
   ```

   Today that is this file's example above, `modules/lambda-web-app/README.md`,
   `modules/dynamodb-single-table/README.md`, `modules/s3-bucket/README.md`
   (two examples in that one — the bucket and its optional DynamoDB lock
   table), `modules/github-oidc-provider/README.md`, and
   `modules/github-oidc-deploy-role/README.md` (two examples in that one — the
   production and staging roles). `CHANGELOG.md` also matches the grep but is a
   historical record, not an advertised version — leave its old `?ref=` values
   as they are.

2. **Add the `CHANGELOG.md` entry**, including any manual migration step a
   consumer has to run. If an existing deployment can't take the new version
   by bumping `?ref=` alone, that is a MAJOR bump and the steps belong in the
   entry, not in your memory.
3. **Check CI is green on `main`** — `fmt -check -recursive`, plus `init` and
   `validate` for every module.
4. **Tag and push it:** `git tag vX.Y.Z && git push origin vX.Y.Z`.
5. **Note which projects need `terraform init -upgrade`**, and tell them.
   Consumers pin by tag, so nothing moves on its own — a tag nobody adopts
   changes nothing. Known consumers: `idea-workflow-example-1` and `n8nDemo`
   (live — treat any migration step there as a real change, not a formality).
   `CalculatorExample` deliberately does not consume these modules.

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every PR and
push to `main`: `terraform fmt -check -recursive` at the repo root, then
`terraform init -backend=false` and `terraform validate` for every directory
under `modules/`. Modules are discovered at runtime, so adding one doesn't
mean remembering to add it here too.

This is the only check that always runs. Nothing downstream substitutes for
it: a generated project runs `terraform fmt -check` against its own root
config, which never descends into a module fetched from here by tag — so no
consumer will ever tell you this repo's source is unformatted or invalid.

## Formatting (enable the hook once per clone)

```bash
git config core.hooksPath .githooks
```

`.githooks/pre-commit` refuses a commit whose staged `.tf`/`.tfvars` files
aren't `terraform fmt`-clean. Git never enables a committed hook
automatically, so a fresh clone needs that one command — until it's run,
the hook is inert.

The hook duplicates CI's fmt check on purpose, and is not a substitute for
it: it's the fast local copy that saves a round trip through a red build,
while CI is what actually can't be skipped. A hook needs that per-clone
`git config` to do anything at all, and `git commit --no-verify` walks past
it even once enabled.

The hook checks staged content, not the working tree, and refuses rather
than reformatting — see the comments in the hook itself for both trade-offs.
To fix what it flags:

```bash
terraform fmt -recursive && git add -u
```

## Adding a module

1. New directory under `modules/`, following the existing shape:
   `versions.tf` (required_providers only, no `provider` block — that's the
   root config's job), `variables.tf`, `main.tf`, `outputs.tf`, `README.md`
   with a usage example.
2. Keep modules single-purpose and composable — `lambda-web-app` doesn't
   know about DynamoDB, `dynamodb-single-table` doesn't know about Lambda,
   `github-oidc-provider` doesn't know about roles; a root config wires them
   together and attaches whatever IAM permissions the pairing actually needs.
3. If it provisions anything outside AWS Always Free, give it a
   `cost_acknowledged` bool and a `lifecycle` precondition that fails the plan
   when the configuration is billable and the flag is false — see
   `dynamodb-single-table` for the pattern, and `project-template`'s
   `STANDARDS.md` for the rule it implements. If it *can't* provision anything
   billable, say so in its README — an absent gate should read as a decision,
   not an omission. The OIDC modules do this: IAM is free.
4. Log anything hard to reverse in [`docs/decisions.md`](docs/decisions.md) —
   what was chosen, why, and why not the obvious alternative. A module README
   says what a module is; that file says why it is that.
5. Tag a new version once it's used successfully by at least one real
   project, following the release checklist above.
