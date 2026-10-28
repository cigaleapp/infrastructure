terraform {
  required_version = ">= 1.16.6"

  required_providers {
    hyperfluid = {
      source  = "tf-registry.ai.meso.umontpellier.fr/nudibranches-tech/hyperfluid"
      version = "0.11.0"
    }
  }
}

provider "hyperfluid" {}

data "hyperfluid_environment" "this" {
  name = "terraforma"
}

# One-time bootstrap: creates the bucket that stores the main configuration's
# remote state, then mints S3 credentials for it.
#
#   cd bootstrap
#   terraform init
#   terraform apply
#
# Capture the `s3_endpoint`, `s3_access_key` and `s3_secret_key` outputs:
#   - s3_endpoint   -> GitHub secret TF_S3_ENDPOINT (and locally: AWS_ENDPOINT_URL)
#   - s3_access_key -> GitHub secret TF_S3_ACCESS_KEY (and locally: AWS_ACCESS_KEY_ID)
#   - s3_secret_key -> GitHub secret TF_S3_SECRET_KEY (and locally: AWS_SECRET_ACCESS_KEY)
#
# After the bucket exists, the main configuration can be migrated with:
#   terraform init -migrate-state
#
# This directory uses the default local backend on purpose: the main
# configuration's backend "s3" block needs the bucket to already exist.
resource "hyperfluid_bucket" "terraform_state" {
  env  = data.hyperfluid_environment.this.id
  name = "biodimedia-terraform-state"
}

data "hyperfluid_bucket_credentials" "terraform_state" {
  env         = data.hyperfluid_environment.this.id
  bucket_name = hyperfluid_bucket.terraform_state.name
}

output "s3_endpoint" {
  description = "S3 endpoint to use with the main configuration's backend (AWS_ENDPOINT_URL)."
  value       = data.hyperfluid_bucket_credentials.terraform_state.endpoint
}

output "s3_access_key" {
  description = "S3 access key id for the state bucket (AWS_ACCESS_KEY_ID)."
  value       = data.hyperfluid_bucket_credentials.terraform_state.access_key
}

output "s3_secret_key" {
  description = "S3 secret key for the state bucket (AWS_SECRET_ACCESS_KEY). Treat as sensitive."
  value       = data.hyperfluid_bucket_credentials.terraform_state.secret_key
  sensitive   = true
}
