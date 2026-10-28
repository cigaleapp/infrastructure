terraform {
  # >= 1.11 is required: hyperfluid_secret.value is a write-only argument.
  required_version = ">= 1.16.6"

  required_providers {
    hyperfluid = {
      source  = "tf-registry.ai.meso.umontpellier.fr/nudibranches-tech/hyperfluid"
      version = "0.11.0"
    }
  }

  # Remote state on Hyperfluid's S3-compatible object storage.
  # The bucket is provisioned once via the `bootstrap/` configuration.
  # Endpoint and credentials are read from the environment so they can be
  # supplied by CI secrets without being committed:
  #   AWS_ENDPOINT_URL      (S3 endpoint from the bootstrap `s3_endpoint` output)
  #   AWS_ACCESS_KEY_ID     (bootstrap `s3_access_key` output)
  #   AWS_SECRET_ACCESS_KEY (bootstrap `s3_secret_key` output)
  #   AWS_REGION            (any value; Ceph ignores it, e.g. "default")
  backend "s3" {
    bucket         = "biodimedia-terraform-state"
    key            = "terraform.tfstate"
    region         = "default"
    use_path_style = true
    use_lockfile   = true

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
  }
}

# Credentials: `hfctl auth login --service-account ./service_account.json`
# then `hfctl tf auth`. Or set HYPERFLUID_CREDENTIALS (e.g. in CI).
provider "hyperfluid" {}
