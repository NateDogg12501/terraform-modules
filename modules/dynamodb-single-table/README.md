# dynamodb-single-table

A single DynamoDB table with an arbitrary set of GSIs, defaulting to
`PROVISIONED` billing (AWS Always Free covers 25 RCU/25 WCU/25GB **per
account+region, shared across all tables** — keep that in mind before this
module's callers add up across several projects in the same account).

## Usage

```hcl
module "table" {
  source = "git::https://github.com/NateDogg12501/terraform-modules.git//modules/dynamodb-single-table?ref=v1.0.0"

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
