terraform {
  # >= 1.11 is required: hyperfluid_secret.value is a write-only argument.
  required_version = ">= 1.11"

  required_providers {
    hyperfluid = {
      # TODO: the provider reference doc does not state the registry address.
      # Replace with the one given in Hyperfluid's Terraform guide.
      source = "REPLACE_ME/hyperfluid"
    }
  }
}

# Credentials: `hfctl auth login --service-account ./service_account.json`
# then `hfctl tf auth`. Or set HYPERFLUID_CREDENTIALS (e.g. in CI).
provider "hyperfluid" {}
