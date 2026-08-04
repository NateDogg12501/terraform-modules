# Deliberately still using hash_key/range_key (deprecated in provider v6)
# rather than their key_schema replacement: as of mid-2026 there are open,
# unresolved provider bugs specifically around key_schema +
# global_secondary_index — perpetual drift, and (worse) removing a GSI under
# key_schema syntax deleting and recreating ALL GSIs on the table.
# hash_key/range_key don't have this problem. Revisit once those are fixed
# upstream; the deprecation warning is cosmetic in the meantime, not a
# functional issue. (Carried over from CalculatorExample's original
# hand-written table, where this was first hit.)
locals {
  # Summed across the base table and every GSI, because DynamoDB's free
  # allowance is account-wide, not per-resource — a table that provisions
  # 5 RCU on itself and 5 on each of four GSIs has provisioned 25.
  #
  # Both are 0 under PAY_PER_REQUEST: the capacity variables are ignored in
  # that mode (see read_capacity/write_capacity below), so folding them into
  # the total would be meaningless. On-demand is caught by its own term in
  # the precondition instead.
  provisioned_read = var.billing_mode == "PROVISIONED" ? sum(concat(
    [var.read_capacity],
    [for gsi in var.global_secondary_indexes : gsi.read_capacity],
  )) : 0

  provisioned_write = var.billing_mode == "PROVISIONED" ? sum(concat(
    [var.write_capacity],
    [for gsi in var.global_secondary_indexes : gsi.write_capacity],
  )) : 0

  # PAY_PER_REQUEST is NOT covered by the Always Free tier. The 25 RCU/25 WCU
  # allowance is specifically for *provisioned* capacity; on-demand bills per
  # request from the very first one. It is the easiest accidental charge in
  # this module, which is why it gates even at zero traffic.
  within_always_free = (
    var.billing_mode == "PROVISIONED" &&
    local.provisioned_read <= 25 &&
    local.provisioned_write <= 25
  )
}

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

  # The cost gate. Standard: AWS Always Free unless logged in
  # docs/decisions.md and explicitly confirmed — a precondition rather than a
  # variable validation because it has to see the *combination* of billing
  # mode and summed capacity, which no single variable can.
  #
  # Fails at plan time, so a billable configuration cannot be applied by
  # accident; it can only be applied by someone who set cost_acknowledged
  # deliberately. Default settings (PROVISIONED, 5/5, no GSIs) are inside the
  # free tier and never trip it.
  #
  # Note what this can and cannot see: the 25 RCU/25 WCU allowance is shared
  # per account+region across every table in every project, and a module only
  # knows its own numbers. Passing this check means "this table alone doesn't
  # exceed the allowance" — not "your account is still free". That part stays
  # a human check.
  lifecycle {
    precondition {
      condition     = local.within_always_free || var.cost_acknowledged
      error_message = <<-EOT
        This table's configuration is billable and cost_acknowledged is false.
          billing_mode:          ${var.billing_mode}${var.billing_mode == "PAY_PER_REQUEST" ? " (on-demand is NOT in the Always Free tier — it bills per request from the first one)" : ""}
          provisioned read/write: ${local.provisioned_read}/${local.provisioned_write} (Always Free covers 25/25, summed over the table and all its GSIs)
        Either bring it back inside the free tier, or log the decision in your
        project's docs/decisions.md and set cost_acknowledged = true.
      EOT
    }
  }
}
