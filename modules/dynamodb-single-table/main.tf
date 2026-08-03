# Deliberately still using hash_key/range_key (deprecated in provider v6)
# rather than their key_schema replacement: as of mid-2026 there are open,
# unresolved provider bugs specifically around key_schema +
# global_secondary_index — perpetual drift, and (worse) removing a GSI under
# key_schema syntax deleting and recreating ALL GSIs on the table.
# hash_key/range_key don't have this problem. Revisit once those are fixed
# upstream; the deprecation warning is cosmetic in the meantime, not a
# functional issue. (Carried over from CalculatorExample's original
# hand-written table, where this was first hit.)
resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key
  range_key    = var.range_key

  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type
      read_capacity   = var.billing_mode == "PROVISIONED" ? global_secondary_index.value.read_capacity : null
      write_capacity  = var.billing_mode == "PROVISIONED" ? global_secondary_index.value.write_capacity : null
    }
  }
}
