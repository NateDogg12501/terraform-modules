terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 5.34 made thumbprint_list optional for this resource; ~> 6.0 matches
      # the rest of this repo. See main.tf for why we leave it unset.
      version = "~> 6.0"
    }
  }
}
