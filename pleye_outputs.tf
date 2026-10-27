# Outputs for the Pleye deployment (see pleye.tf).

# ---- Endpoints --------------------------------------------------------------

output "pleye_url" {
  value = hyperfluid_container_app.pleye.endpoint
}

# ---- Databases --------------------------------------------------------------

output "pleye_db_write_endpoint" {
  value = hyperfluid_managed_postgresql.pleye_db.write_endpoint
}

# ---- Console follow-up ------------------------------------------------------
# The provider cannot set env vars or secret_refs yet. After `terraform apply`,
# configure the app in the Hyperfluid console using the values below. The
# MASTER_KEY is environment-specific: pull it from the "default" environment
# or set a new one.

output "pleye_env_reference" {
  description = "Env vars / secret_refs to set in the Hyperfluid console for pleye."
  value = {
    pleye = {
      VERSION      = "hf0"
      DATABASE_URL = "secret_ref: biodimedia/dbaas/postgres/pleye-db/user/pleye/internal-database-url"
      MASTER_KEY   = "secret_ref: biodimedia/containers/pleye/master-key"
    }
  }
}
