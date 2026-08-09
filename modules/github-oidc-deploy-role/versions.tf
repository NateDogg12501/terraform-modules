terraform {
  # >= 1.9 rather than this repo's usual >= 1.5, and the reason is
  # load-bearing: Terraform 1.9 is the first version whose variable
  # `validation` blocks may reference *other* variables. The check that every
  # entry in subject_claims is scoped to github_repo — the one thing standing
  # between this module and a role assumable by any repository on GitHub — is
  # exactly such a cross-variable check. On 1.8 or older it would silently be
  # unwriteable, so the constraint is here to make that a version error rather
  # than a missing guard. Generated projects already require >= 1.10 for the
  # S3 backend's native locking, so this costs nothing in practice.
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
