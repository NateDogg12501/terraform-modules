# github-oidc-provider

The account-level identity provider that lets GitHub Actions authenticate to
AWS without long-lived access keys. GitHub mints a short-lived OIDC token for
each workflow run; AWS STS exchanges it for temporary credentials against a
role whose trust policy points at this provider.

This is a **prerequisite** module — it has to exist before any CI in the
account can deploy anything. It creates one resource
(`aws_iam_openid_connect_provider`) and nothing else; it does not know about
roles. Pair it with
[`github-oidc-deploy-role`](../github-oidc-deploy-role), which consumes the
`provider_arn` output.

## Usage

Created **once per AWS account**, typically from an account-level bootstrap
config rather than from any individual project:

```hcl
module "github_oidc" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/github-oidc-provider?ref=v2.2.0"
}

output "github_oidc_provider_arn" {
  value = module.github_oidc.provider_arn
}
```

That is the whole interface. `thumbprint_list` and `tags` are the only
variables, and you should not need the first one (see below).

## One per account — `EntityAlreadyExists`

IAM allows exactly **one OIDC provider per issuer URL per account**. If
something already created one for `token.actions.githubusercontent.com` — an
earlier `terraform apply`, a different root config, the AWS console, a
CloudFormation stack — applying this module fails:

```
EntityAlreadyExists: Provider with url https://token.actions.githubusercontent.com already exists.
```

The fix is to adopt the existing provider rather than create a second one.
Its ARN is deterministic, so you can write it out by hand:

```
arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
```

or list it:

```bash
aws iam list-open-id-connect-providers
```

Then import it into this module's state and apply:

```bash
terraform import 'module.github_oidc.aws_iam_openid_connect_provider.github' \
  'arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com'
```

Expect the first plan after importing to show an in-place update if the
existing provider's `client_id_list` or thumbprints differ from what this
module declares — check that diff before applying, since removing an audience
another role depends on will break that role.

If the provider is owned by a *different* Terraform config that you don't want
to take over, don't import it. Look it up instead and pass the ARN straight to
`github-oidc-deploy-role`:

```hcl
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
```

Two configs both managing the same provider is the one arrangement to avoid —
whichever applies last wins, and `terraform destroy` on either one deletes the
provider out from under every role in the account that trusts it.

## Thumbprints

`thumbprint_list` is deliberately left unset. AWS validates
`token.actions.githubusercontent.com` against its own trusted root CA store and
does not use the thumbprint for this endpoint, so pinning one buys nothing and
costs you an outage the next time GitHub rotates a certificate — which is
exactly what happened to everyone who hardcoded `6938fd4d...` when that was the
required practice. The argument still exists on the resource, so the omission
is documented in `main.tf` and in this repo's `docs/decisions.md` rather than
left to look like an oversight.

The variable remains as an escape hatch if AWS ever reverses that. Setting it
is not something a normal deployment should do — and note it doesn't undo
cleanly: the argument is Optional+Computed, so removing it later keeps the last
value you set rather than handing the decision back to AWS.

## Outputs

| Output | Contains |
|---|---|
| `provider_arn` | The provider ARN. This is what `github-oidc-deploy-role` takes as `oidc_provider_arn`. |
| `provider_url` | The issuer URL **with** its scheme: `https://token.actions.githubusercontent.com`. |

`provider_url` is the `iss` claim, not a condition-key prefix. A role's trust
policy keys use the bare host — `token.actions.githubusercontent.com:aud` and
`:sub` — so interpolating this output into a key name produces
`https://token.actions.githubusercontent.com:aud`, which matches nothing and
fails open-looking rather than erroring. `github-oidc-deploy-role` hardcodes
the host for exactly this reason.

## Cost

**No `cost_acknowledged` flag, deliberately.** IAM OIDC providers are free —
there is no per-provider, per-token or per-assume charge — so there is no
billable configuration for a gate to catch. The
[`cost_acknowledged` standard](../../README.md#adding-a-module) applies to
modules that *can* provision something billable; this one cannot.
