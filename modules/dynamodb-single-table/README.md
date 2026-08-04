# dynamodb-single-table

A single DynamoDB table with an arbitrary set of GSIs, defaulting to
`PROVISIONED` billing (AWS Always Free covers 25 RCU/25 WCU/25GB **per
account+region, shared across all tables** — keep that in mind before this
module's callers add up across several projects in the same account).

## Usage

```hcl
module "table" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/dynamodb-single-table?ref=v2.0.0"

  table_name = "my-app-items"
  hash_key   = "id"

  attributes = [
    { name = "id", type = "S" },
    { name = "ownerLower", type = "S" },
  ]

  global_secondary_indexes = [
    {
      name     = "owner-lower-index"
      hash_key = "ownerLower"
    },
  ]
}
```

`attributes` must list every field used as a hash/range key anywhere — on
the table itself or on any GSI — exactly once, matching DynamoDB's own API
shape (attribute type declarations are separate from key schema).

## Cost gate

The standard is **AWS Always Free unless logged in `docs/decisions.md` and
explicitly confirmed**. This module enforces the "explicitly confirmed" half
with a `lifecycle` precondition that fails the **plan** — not the apply — when
the configuration is billable and `cost_acknowledged` is `false` (the
default). You cannot accidentally apply a paid table.

It trips on:

- `billing_mode = "PAY_PER_REQUEST"`. On-demand is **not** in the Always Free
  tier — the 25 RCU/25 WCU allowance is specifically for *provisioned*
  capacity, and on-demand bills per request from the first one. This is the
  easy accidental charge here, which is why it gates even at zero traffic.
- Provisioned capacity summed across the table **and all its GSIs** exceeding
  25 RCU or 25 WCU.

The defaults (`PROVISIONED`, 5/5, no GSIs) are inside the free tier and never
trip it. To apply a billable table on purpose, log why in your project's
`docs/decisions.md` and then set `cost_acknowledged = true` — the flag on its
own satisfies the mechanism but not the standard.

What this cannot check: that 25/25 allowance is shared **per account+region
across every table in every project**, and a module only sees its own numbers.
Passing means this table alone is within the allowance, not that your account
still is.
