# Decisions

One entry per hard-to-reverse decision in this repo, written when it's made
rather than reconstructed later. Same discipline `project-template`'s
`STANDARDS.md` asks of every generated project, applied to the repo those
projects inherit their infrastructure from.

Scope: choices about *this repo's* modules — what a module does, what it
refuses to do, and why the obvious alternative was not taken. A module's
`README.md` says what it is; this file says why it is that.

## 2026-08-09 — `github-oidc-provider` sets no thumbprint

**Decision.** `aws_iam_openid_connect_provider.thumbprint_list` is left unset
(`var.thumbprint_list` defaults to `null`, which Terraform treats as an omitted
argument). The variable exists only as an escape hatch.

**Why.** Thumbprint pinning was originally how IAM verified the IdP's TLS
certificate. In practice that meant every consumer hardcoded a GitHub
leaf/intermediate thumbprint — the `6938fd4d...` and `1c58a3a8...` constants
still copied around the internet — and every consumer broke when GitHub rotated
a certificate. In July 2023 AWS moved to validating
`token.actions.githubusercontent.com` against its own trusted root CA store,
and the thumbprint stopped being used for this endpoint. Pinning one now buys
no security and adds a scheduled outage.

**Why not just omit it silently.** The argument still exists on the resource,
AWS still stores and returns a value, and the internet is full of examples that
set it. Without a comment, a future reader cannot tell an informed omission
from someone who forgot — and "add the thumbprint back" is a plausible, wrong
thing for them to do. Hence the comment in `main.tf`, the section in the
module's README, and this entry.

**Rejected: keep a hardcoded thumbprint anyway, "just in case".** It is not
inert. If AWS ever did consult the list again, a stale pinned value is the
failure mode — an authentication outage across every repository in the account
— whereas an unset list means AWS uses its own trust store.

**Reversal is one-way-ish.** Setting `thumbprint_list` is an in-place update
with no state migration, but it does not undo cleanly: the argument is
Optional+Computed, so removing it later leaves the last value you set in place
rather than returning the decision to AWS. Getting back to "AWS decides" means
setting the value explicitly or replacing the provider — which, since every
role in the account trusts it, is not a casual operation.

## 2026-08-09 — `github-oidc-deploy-role` requires `permissions_boundary_arn`

**Decision.** `permissions_boundary_arn` is a required variable with no
default. A caller that omits it gets a plan error, not an unbounded role.

**Why.** A permissions boundary caps a role's effective permissions to the
intersection of the boundary and whatever policies are attached, so it keeps
holding when the attached policy is wrong — an over-broad `policy_json`, or an
extra policy attached out of band later. It is the control that survives the
mistakes the other controls are the mistakes *in*.

The deciding factor is who calls this module. These roles are created by an
automated provisioner, per repository per environment, which is exactly the
setting where an optional security argument gets left out once and nobody
notices: the role works, deploys succeed, and the only symptom is invisible.
An unbounded deploy role and a bounded one look identical in the console.

**Rejected: optional with a default of `null`.** Matches the AWS provider's own
shape and reads as the more flexible choice, but it makes the safe path the one
you have to remember. Every other guard in this repo defaults to safe
(`cost_acknowledged = false`, `force_destroy = false`); this is the same
principle with a required argument instead of a default, because there is no
safe *value* to default to — only a safe requirement.

**Rejected: create the boundary policy in this module too.** The boundary is
account-scoped: one policy shared by every deploy role in the account. A module
that created its own would produce N boundaries that drift apart, and each role
would define its own ceiling — which is not a ceiling. It belongs in the
account bootstrap config, next to `github-oidc-provider`.

**Cost of being wrong.** A boundary too tight fails a deploy loudly and is a
one-line fix. Required is the recoverable direction.

**Reversal.** Give the variable a default. That is a MINOR change for
consumers, but it silently weakens every role created afterwards, so it would
need its own entry here.

## 2026-08-09 — `subject_claims` is validated against `github_repo`, and the module requires Terraform >= 1.9

**Decision.** Every `subject_claims` entry must start with
`repo:<github_repo>:`, checked in a variable `validation` block.
`github_repo` is separately validated to contain no wildcard. The module
declares `required_version = ">= 1.9"` (the rest of this repo asks `>= 1.5`).

**Why.** The trust policy's `sub` condition is the entire security boundary of
an OIDC deploy role. A pattern that isn't anchored to one repository is
assumable by whatever else it matches — `repo:*` is every repository on GitHub,
including one an attacker creates on demand — and the resulting role looks
completely ordinary. The wildcard check on `github_repo` exists because
otherwise the first check could be satisfied by validating against a wildcard,
proving nothing.

**Why the version bump is load-bearing.** Terraform 1.9 is the first release
whose variable validation can reference *other* variables, which is what
comparing `subject_claims` to `github_repo` needs. On 1.8 the rule cannot be
written, so without the constraint the guard would simply be absent on older
Terraform rather than failing. Generated projects already require >= 1.10 for
the S3 backend's native locking, so the constraint costs nothing in practice.

**Rejected: a `lifecycle` precondition on the role instead.** It would work on
any Terraform version and fail at the same point (plan). But this is a
single-variable-shape check, which is what `validation` is for, and the
precondition reads as a cost gate here — that pattern already means something
specific in this repo (`dynamodb-single-table`, `s3-bucket`).

**Known limit.** `terraform validate` does not evaluate a child module's
variable validations, so a consuming project's `validate` job stays green on a
config this rejects. The check fires at plan, which always precedes apply, so
nothing unsafe can be applied — but a green `validate` is not evidence the
claims were checked. Documented in the module's README.

**Superseded 2026-08-10 by the entry below.** The anchoring rule survives; the
mechanism and the version constraint do not.

## 2026-08-10 — the subject prefix is constructed, not validated (v3.0.0)

**Decision.** `subject_claims` is replaced by `subject_suffixes`.
`github_owner_id` and `github_repo_id` become required. The module builds
`repo:<owner>@<owner_id>/<name>@<repo_id>:` and prepends it to each suffix.
`required_version` drops back to `>= 1.5`.

**What forced it.** GitHub's OIDC `sub` claim embeds numeric owner and
repository IDs. Every trust policy built by v2.x targets
`repo:<owner>/<name>:...`, matches no token GitHub will mint, and fails with
`Not authorized to perform sts:AssumeRoleWithWebIdentity` — an error that names
neither the subject nor the claim. Every role v2.x ever created is unassumable.

**How it was found, which is the uncomfortable part.** v2.2.0 was released,
reviewed, and consumed by `aws-account` before anything ever exercised it. The
module's tests, its validations and two rounds of review all passed on a design
that could not work, because every one of them checked the config against the
*documented* claim format rather than against a real token. It surfaced on the
first real workflow run, in the phase after the one that shipped it.

**Do not trust the API for this.** `GET
/repos/{owner}/{repo}/actions/oidc/customization/sub` returns
`use_immutable_subject: false` while the tokens it mints carry the IDs anyway.
The only authoritative source is a decoded token, which is why the module's
README now carries the two-line recipe for reading one.

**Why the mechanism changed and not just the string.** The old guard was a
validation: accept whole `sub` patterns, reject any not starting with
`repo:<github_repo>:`. That is only as correct as the format it encodes, and
when the format changed it did not fail — it went on passing while guarding
nothing, and would have kept accepting a now-meaningless pattern indefinitely.
Building the prefix instead means the anchor is not an assertion about the
input but a property of the output: there is no `subject_suffixes` value that
escapes it. A construction that is wrong breaks everything immediately and
visibly; a validation that is wrong breaks nothing and protects nothing.

That is the transferable rule, and it is worth more than this fix: **prefer
making the unsafe state unrepresentable over checking that it did not
occur** — especially for a rule expressed against an external format you do
not control.

**Consequence for the version constraint.** `>= 1.9` existed solely so the
cross-variable validation could be written. With no cross-variable reference
left, the constraint no longer describes anything, so it returns to the repo's
`>= 1.5`. Recorded here rather than in the README, which describes only what is
currently true.

**Rejected: keep `subject_claims` as a deprecated second input.** It would have
been additive — a MINOR bump, no consumer edits forced. But every value it can
accept is now a value that produces an unassumable role, so keeping it means
keeping a path that provably cannot work, for compatibility with zero working
deployments. A MAJOR bump costs one re-pin today and nothing later; the tag was
one day old and `aws-account` its only consumer.

**Rejected: an `owner/repo`-shaped `github_repo` carrying the IDs inline**
(e.g. `"NateDogg12501@28988424/aws-account@1329306836"`). One variable instead
of three, but it makes the human-readable repository name unparseable for the
role description, and it invites a caller to paste a prefix they built by hand —
the exact error the construction exists to remove.
