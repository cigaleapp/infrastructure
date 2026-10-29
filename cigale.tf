# Cigale platform on Hyperfluid (biodimedia environment)
#
# Mirrors the apps already running in the "default" environment, plus the
# databases and buckets that were deleted there but are needed here.
#
#   cigale-app                  -> hyperfluid_container_app
#   cigale-dev                  -> hyperfluid_container_app
#   cigale-beamup               -> hyperfluid_container_app
#   cigale-beamup-smtp          -> hyperfluid_container_app
#   cigale-cors-proxy           -> hyperfluid_container_app
#   cigale-github-actions-runner-> hyperfluid_container_app
#
#   cigale-beamup-db            -> hyperfluid_managed_postgresql (recreated)
#   cigale-dev-files            -> hyperfluid_bucket (recreated)
#   cigale-beamup-attachments   -> hyperfluid_bucket (recreated)
#
#   cigale-beamup -> cigale-beamup-smtp:25  -> hyperfluid_service_link
#   cigale-beamup -> cigale-beamup-db       -> hyperfluid_service_link
#
# pleye, pleye-db and db-studio live in their own deployment files
# (pleye.tf, db_studio.tf).
#
# KNOWN GAPS in this provider version (hyperfluid_container_app has only
# scalar attributes - env/secret/mount blocks land in a follow-up):
#   1. No env vars: every app below needs environment variables that cannot be
#      set here. See the per-app comments and the `app_env_reference` output,
#      and set them in the Hyperfluid console after `terraform apply`.
#   2. No secret_refs: cigale-beamup (DATABASE_URL) references a
#      managed-postgres internal URL; wire it up in the console.
#   3. No file mounts: cigale-dev mounts an inline Caddyfile at
#      /etc/caddy/Caddyfile; recreate it in the console.
#
# NOTE on ports: hfctl does not report per-app ports, so the port numbers below
# are inferred from each app's role. Adjust the `ports` blocks if an app
# listens elsewhere.

# ---------------------------------------------------------------------------
# Databases (deleted in "default", recreated here)
# ---------------------------------------------------------------------------

resource "hyperfluid_managed_postgresql" "beamup_db" {
  env              = local.env
  name             = "cigale-beamup-db"
  database_name    = "beamup"
  engine           = "postgresql"
  version          = "17"
  node_tier        = var.beamup_db_node_tier
  storage_capacity = var.beamup_db_storage_gb
  configuration    = var.postgres_configuration
  description      = "Cigale BeamUp application database"
  tags             = ["cigale", "beamup", "terraform"]
}

# The running app connects through a dedicated role.
resource "hyperfluid_managed_postgresql_user" "beamup" {
  managed_postgresql = hyperfluid_managed_postgresql.beamup_db.id
  username           = "beamup"
  permission_level   = "editor"
  description        = "Role used by the cigale-beamup app"
}

# ---------------------------------------------------------------------------
# Buckets (deleted in "default", recreated here)
# ---------------------------------------------------------------------------

resource "hyperfluid_bucket" "cigale_dev_files" {
  env  = local.env
  name = "cigale-dev-files"
}

data "hyperfluid_bucket_credentials" "cigale_dev_files" {
  env         = local.env
  bucket_name = hyperfluid_bucket.cigale_dev_files.name
}

resource "hyperfluid_bucket" "cigale_beamup_attachments" {
  env  = local.env
  name = "cigale-beamup-attachments"
}

data "hyperfluid_bucket_credentials" "cigale_beamup_attachments" {
  env         = local.env
  bucket_name = hyperfluid_bucket.cigale_beamup_attachments.name
}

# ---------------------------------------------------------------------------
# cigale-app (client-side app, no env vars)
# ---------------------------------------------------------------------------

resource "hyperfluid_container_app" "cigale_app" {
  env              = local.env
  slug             = "cigale-app"
  image_repository = var.cigale_app_image_repository
  image_tag        = var.cigale_app_image_tag
  resource_tier    = var.cigale_app_tier
  enabled          = true
  autoscaling      = var.autoscaling_1_3

  ports = [
    { name = "http", port = 80, protocol = "HTTP", primary = true },
  ]

  expose_to_internet = true
  tags               = ["cigale", "terraform"]
}

# ---------------------------------------------------------------------------
# cigale-dev (dev-deployments server behind Caddy)
#   Needs (console): AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT_URL,
#   AWS_DEFAULT_REGION, and the inline Caddyfile mounted at /etc/caddy/Caddyfile.
# ---------------------------------------------------------------------------

resource "hyperfluid_container_app" "cigale_dev" {
  env              = local.env
  slug             = "cigale-dev"
  image_repository = var.cigale_dev_image_repository
  image_tag        = var.cigale_dev_image_tag
  resource_tier    = var.cigale_dev_tier
  autoscaling      = var.autoscaling_1_3
  enabled          = var.apps_enabled

  ports = [
    { name = "http", port = 80, protocol = "HTTP", primary = true },
  ]

  env_vars = [
    { name = "AWS_ACCESS_KEY_ID", value = data.hyperfluid_bucket_credentials.cigale_dev_files.access_key },
    { name = "AWS_SECRET_ACCESS_KEY", value = data.hyperfluid_bucket_credentials.cigale_dev_files.secret_key },
    { name = "AWS_ENDPOINT_URL", value = data.hyperfluid_bucket_credentials.cigale_dev_files.endpoint },
    { name = "AWS_DEFAULT_REGION", value = "default" },
    { name = "DEPLOYMENT_DOMAIN", value = var.cigale_dev_domain }
  ]

  file_mounts = [{
    mount_path = "/etc/caddy/Caddyfile",
    content    = <<-EOT
		{
			filesystem bucket s3 {
				bucket ${data.hyperfluid_bucket_credentials.cigale_dev_files.bucket_name}
				region default

				endpoint ${data.hyperfluid_bucket_credentials.cigale_dev_files.endpoint}
				# profile <profile>
				use_path_style 
			}

			log default { 
			   level DEBUG
			}
		}

		http://${var.cigale_dev_domain} {
			file_server {
				fs bucket
				browse
			}

			log {
				output stdout
			}

			handle_errors {
				respond "{err.status_code} {err.status_text}"
			}
		}
	EOT
  }]

  expose_to_internet = true
  tags               = ["cigale", "developers", "terraform"]
}

# ---------------------------------------------------------------------------
# cigale-beamup (BeamUp server)
#   Needs (console): PROD, ALLOWED_ORIGINS, SMTP_HOST, SMTP_PORT, MAILS_FROM,
#   S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY, S3_ENDPOINT, S3_DEFAULT_REGION,
#   S3_BUCKET, and the DATABASE_URL secret_ref to cigale-beamup-db.
# ---------------------------------------------------------------------------

resource "hyperfluid_container_app" "cigale_beamup" {
  env              = local.env
  slug             = "cigale-beamup"
  image_repository = var.cigale_beamup_image_repository
  image_tag        = var.cigale_beamup_image_tag
  resource_tier    = var.cigale_beamup_tier
  autoscaling      = var.autoscaling_1_3
  enabled          = var.apps_enabled

  ports = [
    { name = "http", port = 3000, protocol = "HTTP", primary = true },
  ]


  env_vars = [
    { name = "S3_ACCESS_KEY_ID", value = data.hyperfluid_bucket_credentials.cigale_beamup_attachments.access_key },
    { name = "S3_SECRET_ACCESS_KEY", value = data.hyperfluid_bucket_credentials.cigale_beamup_attachments.secret_key },
    { name = "S3_ENDPOINT", value = data.hyperfluid_bucket_credentials.cigale_beamup_attachments.endpoint },
    { name = "S3_DEFAULT_REGION", value = "default" },
    { name = "S3_BUCKET", value = hyperfluid_bucket.cigale_beamup_attachments.name },
    { name = "PROD", value = "true" },
    { name = "ALLOWED_ORIGINS", value = "https://${var.cigale_domain},https://cigaleapp.github.io" },
    { name = "SMTP_HOST", value = "ca-${hyperfluid_container_app.cigale_beamup_smtp.slug}" },
    { name = "SMTP_PORT", value = "25" },
    { name = "MAILS_FROM", value = "noreply@${var.cigale_domain}" },
    { name = "DATABASE_URL", secret = "${var.env_name}/dbaas/postgres/${hyperfluid_managed_postgresql.beamup_db.slug}/user/${hyperfluid_managed_postgresql_user.beamup.username}/internal-database-url" }
  ]

  expose_to_internet = true
  tags               = ["cigale", "beamup", "prod", "terraform"]
}

# ---------------------------------------------------------------------------
# cigale-beamup-smtp (SMTP relay for beamup)
#   Needs (console): MAILNAME.
# ---------------------------------------------------------------------------

resource "hyperfluid_container_app" "cigale_beamup_smtp" {
  env              = local.env
  slug             = "cigale-beamup-smtp"
  image_repository = var.cigale_beamup_smtp_image_repository
  image_tag        = var.cigale_beamup_smtp_image_tag
  resource_tier    = var.cigale_beamup_smtp_tier
  replicas         = 1
  enabled          = var.apps_enabled

  ports = [
    { name = "smtp", port = 25, protocol = "TCP" },
  ]

  env_vars = [
    { name = "MAILNAME", value = "data-terra.ai.meso.umontpellier.fr" }
  ]

  expose_to_internet = false
  tags               = ["cigale", "beamup", "terraform"]
}

# ---------------------------------------------------------------------------
# cigale-cors-proxy
#   Needs (console): PORT.
# ---------------------------------------------------------------------------

resource "hyperfluid_container_app" "cigale_cors_proxy" {
  env              = local.env
  slug             = "cigale-cors-proxy"
  image_repository = var.cigale_cors_proxy_image_repository
  image_tag        = var.cigale_cors_proxy_image_tag
  resource_tier    = var.cigale_cors_proxy_tier
  autoscaling      = var.autoscaling_1_5
  enabled          = var.apps_enabled

  ports = [
    { name = "http", port = 3000, protocol = "HTTP", primary = true },
  ]

  env_vars = [
    { name = "PORT", value = "3000" }
  ]

  expose_to_internet = true
  tags               = ["cigale", "prod", "terraform"]
}

# ---------------------------------------------------------------------------
# Github Actions runner (WIP)
# ---------------------------------------------------------------------------

data "hyperfluid_virtual_machine_images" "vm_catalog" {
  env = local.env
}

locals {
  ubuntu = data.hyperfluid_virtual_machine_images.vm_catalog.images[0]
}

resource "hyperfluid_virtual_machine" "cigale_github_actions" {
  env              = local.env
  name             = "cigale-github-actions"
  cpu              = "4"
  memory           = "16Gi"
  disk             = "40Gi"
  image_source_ref = local.ubuntu.image_source_ref
  image_key        = local.ubuntu.image_key
  running          = false
}


# ---------------------------------------------------------------------------
# Service links
# ---------------------------------------------------------------------------
# Under the default "lenient" isolation these only record intent; under
# "strict" they are what permits the traffic.

# cigale-beamup talks to its SMTP relay on port 25 (the only link that existed
# in "default").
resource "hyperfluid_service_link" "beamup_smtp" {
  env = local.env

  consumer = {
    kind = "ContainerApp"
    name = hyperfluid_container_app.cigale_beamup.slug
  }

  target = {
    kind = "ContainerApp"
    name = hyperfluid_container_app.cigale_beamup_smtp.slug
  }

  target_ports = [
    { port = 25, protocol = "TCP" },
  ]
}

# Database link so the app can reach its cluster.
locals {
  db_links = {
    beamup_db = {
      consumer = hyperfluid_container_app.cigale_beamup.slug
      target   = hyperfluid_managed_postgresql.beamup_db.slug
    }
  }
}

resource "hyperfluid_service_link" "databases" {
  for_each = local.db_links

  env = local.env

  consumer = {
    kind = "ContainerApp"
    name = each.value.consumer
  }

  target = {
    kind = "ManagedPostgreSQL"
    name = each.value.target
  }
}
