terraform {
  # >= 1.5, matching the rest of this repo. Through v2.x this module asked for
  # >= 1.9, because the guard that kept the role from being assumable by an
  # unrelated repository was a variable `validation` referencing *another*
  # variable, which 1.9 was the first release to allow. v3.0.0 replaced that
  # check with a construction — the subject prefix is built from github_repo
  # and the owner/repo IDs, so a caller cannot express an unanchored claim —
  # and the constraint went with the reason for it. See docs/decisions.md.
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
