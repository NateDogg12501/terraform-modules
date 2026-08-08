# Defaults land inside AWS's Always Free tier: SSE-S3 encryption (no KMS
# charges), BucketOwnerEnforced ownership (no ACL costs or drift), and a
# noncurrent-version expiration rule so a bucket that's overwritten a lot
# (e.g. Terraform state) doesn't quietly outgrow the 5GB storage allowance.
#
# What this module cannot gate: the Always Free limits (5GB storage, 20,000
# GET, 2,000 PUT/COPY/POST/LIST per month) are usage-based, not
# configuration-based, so no plan-time precondition can see them. The
# cost_acknowledged gate below only catches configuration choices that are
# billable regardless of how much you store or how often you touch it.
resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  # The cost gate. Standard: AWS Always Free unless logged in
  # docs/decisions.md and explicitly confirmed.
  lifecycle {
    precondition {
      condition     = var.sse_algorithm == "AES256" || var.cost_acknowledged
      error_message = <<-EOT
        sse_algorithm is "${var.sse_algorithm}" and cost_acknowledged is false.
          AES256 (SSE-S3, AWS-owned key) is free. Any KMS-backed algorithm
          bills per API request beyond KMS's own free tier, and a
          customer-managed key adds a flat $1/month on top of that.
        Either use AES256, or log the decision in your project's
        docs/decisions.md and set cost_acknowledged = true.
      EOT
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.sse_algorithm == "aws:kms" ? var.kms_key_id : null
    }
    # Only meaningful (and only reduces cost) under SSE-KMS; harmless no-op
    # under SSE-S3.
    bucket_key_enabled = var.sse_algorithm == "aws:kms"
  }
}

# Disables ACLs entirely in favor of IAM/bucket policies — AWS's current
# recommended default, and one less thing that can drift or be misconfigured
# for free.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# See noncurrent_version_expiration_days: skipped entirely (rather than a
# rule with a 0-day expiration, which S3 rejects) when the caller sets it to
# 0, since disabling the rule is what "0" is documented to mean here.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.noncurrent_version_expiration_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  # The versioning configuration must exist before a rule referencing
  # noncurrent versions is created.
  depends_on = [aws_s3_bucket_versioning.this]
}

# Free, and closes the easiest accidental-exposure path: an object PUT or GET
# made over plain HTTP instead of HTTPS.
data "aws_iam_policy_document" "require_tls" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "require_tls" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.require_tls.json
}
