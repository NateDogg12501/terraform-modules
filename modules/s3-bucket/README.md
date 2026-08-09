# s3-bucket

A general-purpose S3 bucket, defaulting to settings that stay inside AWS's
**Always Free** tier: SSE-S3 encryption, all-ACLs-disabled ownership, public
access fully blocked, TLS-only bucket policy, and a lifecycle rule that
expires old object versions before they can quietly outgrow the free storage
allowance.

Since mid-2024 the S3 Free Tier no longer expires after 12 months — for both
new and existing accounts it's now perpetual: **5GB of S3 Standard storage,
20,000 GET requests, and 2,000 PUT/COPY/POST/LIST requests per month**, plus
the account-wide 100GB/month data transfer out allowance shared with every
other service. That makes S3 usable under this repo's Always Free standard,
with one caveat this module can't check for you — see
[Cost gate](#cost-gate) below.

## Usage: backing Terraform state

The use case that motivated this module — an S3 bucket to hold a project's
own `terraform.tfstate` instead of a local file:

```hcl
module "tf_state" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/s3-bucket?ref=v2.2.0"

  bucket_name = "my-app-tfstate"
}

output "tf_state_bucket" {
  value = module.tf_state.bucket_id
}
```

Then point the root config's backend at it (this is plain Terraform
configuration, not something this module can set for you — the backend a
config uses has to be known before that config's own resources, including
this bucket, can exist):

```hcl
terraform {
  backend "s3" {
    bucket       = "my-app-tfstate"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # Terraform >= 1.10: native S3 locking, no DynamoDB needed
  }
}
```

On Terraform < 1.10 (no `use_lockfile`), pair this module with
[`dynamodb-single-table`](../dynamodb-single-table) for state locking instead
— its defaults (`PROVISIONED`, 5/5) are also inside the Always Free tier:

```hcl
module "tf_lock" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/dynamodb-single-table?ref=v2.2.0"

  table_name = "my-app-tfstate-lock"
  hash_key   = "LockID"
  attributes = [{ name = "LockID", type = "S" }]
}
```

```hcl
terraform {
  backend "s3" {
    bucket         = "my-app-tfstate"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "my-app-tfstate-lock"
  }
}
```

The classic bootstrapping wrinkle applies either way: the bucket (and lock
table, if used) must exist and be applied with a local backend *before* you
can migrate the same config onto the S3 backend it just created.

## Cost gate

The standard is **AWS Always Free unless logged in `docs/decisions.md` and
explicitly confirmed**. This module enforces the "explicitly confirmed" half
with a `lifecycle` precondition that fails the **plan** — not the apply —
when `sse_algorithm` is set to `"aws:kms"` and `cost_acknowledged` is `false`
(the default). SSE-S3 (`AES256`, the default) uses an AWS-owned key and is
free; SSE-KMS bills per API request beyond KMS's own free tier, and a
customer-managed key adds a flat $1/month regardless of usage.

What this **cannot** check, unlike `dynamodb-single-table`'s capacity gate:
S3's Always Free limits (5GB storage, 20,000 GET, 2,000 PUT/COPY/POST/LIST
per month) are **usage-based**, not configuration-based — nothing about a
`terraform plan` can see how much data you'll actually store or how often
you'll touch it. `noncurrent_version_expiration_days` (default `90`) exists
to keep one common usage pattern — a bucket that's overwritten a lot, like
Terraform state applied on every run — from silently accumulating versions
past the 5GB line. It does not, and cannot, guarantee you'll stay under it.

## What it doesn't manage

Deliberately narrow, matching `dynamodb-single-table`'s scope: this module
creates the bucket and its own settings, nothing else. No bucket policy
beyond the TLS-only deny rule, no cross-region replication, no static
website hosting, no CloudFront in front of it. Attach whatever policy your
use case needs (e.g. the `iam:GetRole`-style access a CI runner needs to
read/write state) from your root config, the same way `lambda-web-app`
leaves datastore IAM to its caller.
