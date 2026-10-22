terraform {
  # >= 1.11 is required: hyperfluid_secret.value is a write-only argument.
  required_version = ">= 1.11"

  required_providers {
    hyperfluid = {
      source  = "tf-registry.ai.meso.umontpellier.fr/nudibranches-tech/hyperfluid"
      version = "0.9.0"
    }
  }
}

# Credentials: `hfctl auth login --service-account ./service_account.json`
# then `hfctl tf auth`. Or set HYPERFLUID_CREDENTIALS (e.g. in CI).
provider "hyperfluid" {}
