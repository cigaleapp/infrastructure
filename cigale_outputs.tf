# Outputs for the Cigale platform deployment (see cigale.tf).

# ---- Endpoints --------------------------------------------------------------

output "cigale_app_url" {
  description = "Public endpoint of cigale-app (empty until it runs)."
  value       = hyperfluid_container_app.cigale_app.endpoint
}

output "cigale_dev_url" {
  value = hyperfluid_container_app.cigale_dev.endpoint
}

output "cigale_beamup_url" {
  value = hyperfluid_container_app.cigale_beamup.endpoint
}

output "cigale_cors_proxy_url" {
  value = hyperfluid_container_app.cigale_cors_proxy.endpoint
}

# ---- Databases --------------------------------------------------------------

output "beamup_db_write_endpoint" {
  value = hyperfluid_managed_postgresql.beamup_db.write_endpoint
}

# ---- Buckets ----------------------------------------------------------------

output "cigale_dev_files_bucket" {
  value = hyperfluid_bucket.cigale_dev_files.name
}

output "cigale_beamup_attachments_bucket" {
  value = hyperfluid_bucket.cigale_beamup_attachments.name
}

# ---- Console follow-up ------------------------------------------------------
# The provider cannot set env vars or secret_refs yet. After `terraform apply`,
# configure each app in the Hyperfluid console using the values below. The
# S3/DB credentials are environment-specific: pull the S3 keys with
# `hfctl buckets credentials <bucket> -e biodimedia` and the database URLs
# from the managed-postgres internal endpoints.

output "app_env_reference" {
  description = "Env vars / secret_refs to set in the Hyperfluid console per app."
  value = {
    cigale-dev = {
      AWS_ACCESS_KEY_ID     = "from: hfctl buckets credentials cigale-dev-files -e biodimedia"
      AWS_SECRET_ACCESS_KEY = "from: hfctl buckets credentials cigale-dev-files -e biodimedia"
      AWS_ENDPOINT_URL      = "https://data-terra.s3-gateway.ai.meso.umontpellier.fr"
      AWS_DEFAULT_REGION    = "biodimedia"
      # plus the inline Caddyfile mounted at /etc/caddy/Caddyfile
    }
    cigale-beamup = {
      PROD                = "true"
      ALLOWED_ORIGINS     = "https://cigaleapp.github.io,http://localhost:5173,https://cigale.data-terra.fr,${hyperfluid_container_app.cigale_app.endpoint}"
      SMTP_HOST           = hyperfluid_container_app.cigale_beamup_smtp.slug
      SMTP_PORT           = "25"
      MAILS_FROM          = "beamup@data-terra.ai.meso.umontpellier.fr"
      S3_ACCESS_KEY_ID    = "from: hfctl buckets credentials cigale-beamup-attachments -e biodimedia"
      S3_SECRET_ACCESS_KEY = "from: hfctl buckets credentials cigale-beamup-attachments -e biodimedia"
      S3_ENDPOINT         = "http://data-terra.s3-gateway.ai.meso.umontpellier.fr"
      S3_DEFAULT_REGION   = "biodimedia"
      S3_BUCKET           = hyperfluid_bucket.cigale_beamup_attachments.name
      DATABASE_URL        = "secret_ref: biodimedia/dbaas/postgres/cigale-beamup-db/user/beamup/internal-database-url"
    }
    cigale-beamup-smtp = {
      MAILNAME = "data-terra.ai.meso.umontpellier.fr"
    }
    cigale-cors-proxy = {
      PORT = "3000"
    }
    cigale-github-actions-runner = {
      ORG_NAME      = "cigaleapp"
      RUNNER_NAME   = "dataterra"
      RUNNER_SCOPE  = "org"
      RUNNER_WORKDIR = "/_work"
      ACCESS_TOKEN  = "set manually (GitHub runner token)"
      LABELS        = "hyperfluid,hyperfluid-4xl"
    }
  }
}
