# Outputs for the db-studio deployment (see db_studio.tf).

# ---- Endpoints --------------------------------------------------------------

output "db_studio_url" {
  value = hyperfluid_container_app.db_studio.endpoint
}

# ---- Console follow-up ------------------------------------------------------
# The provider cannot set env vars or secret_refs yet. After `terraform apply`,
# configure the app in the Hyperfluid console using the values below.

output "db_studio_env_reference" {
  description = "Env vars / secret_refs to set in the Hyperfluid console for db-studio."
  value = {
    db-studio = {
      MASTERPASS          = "set manually"
      DATABASE_URL_PLEYE  = "secret_ref: biodimedia/dbaas/postgres/pleye-db/user/pleye/internal-database-url"
      DATABASE_URL_BEAMUP = "secret_ref: biodimedia/dbaas/postgres/cigale-beamup-db/user/beamup/internal-database-url"
    }
  }
}
