# db-studio (Drizzle gateway) on Hyperfluid (biodimedia environment)
#
# Mirrors the app already running in the "default" environment.
#
#   db-studio -> hyperfluid_container_app
#
#   db-studio -> pleye-db        -> hyperfluid_service_link
#   db-studio -> cigale-beamup-db -> hyperfluid_service_link
#
# The linked clusters are declared in pleye.tf (pleye-db) and cigale.tf
# (cigale-beamup-db).
#
# KNOWN GAPS in this provider version (hyperfluid_container_app has only
# scalar attributes - env/secret blocks land in a follow-up):
#   1. No env vars: db-studio needs MASTERPASS; set it in the Hyperfluid
#      console after `terraform apply`.
#   2. No secret_refs: db-studio references DATABASE_URL_PLEYE (pleye-db) and
#      DATABASE_URL_BEAMUP (cigale-beamup-db) internal URLs; wire them up in
#      the console.
#
# NOTE on ports: hfctl does not report per-app ports, so the port number below
# is inferred from the app's role. Adjust the `ports` block if db-studio
# listens elsewhere.

# ---------------------------------------------------------------------------
# db-studio (Drizzle gateway)
#   Needs (console): MASTERPASS, and secret_refs DATABASE_URL_PLEYE (pleye-db)
#   and DATABASE_URL_BEAMUP (cigale-beamup-db).
# ---------------------------------------------------------------------------

locals {
  databases = [
    {
      instance = hyperfluid_managed_postgresql.pleye_db,
      user     = hyperfluid_managed_postgresql_user.pleye
    },
    {
      instance = hyperfluid_managed_postgresql.beamup_db,
      user     = hyperfluid_managed_postgresql_user.beamup
    }
  ]
}

resource "hyperfluid_container_app" "db_studio" {
  env              = local.env
  slug             = "biodimedia-db-studio"
  image_repository = var.db_studio_image_repository
  image_tag        = var.db_studio_image_tag
  resource_tier    = var.db_studio_tier
  enabled          = var.apps_enabled
  autoscaling      = var.autoscaling_1_3

  ports = [
    { name = "http", port = 4983, protocol = "HTTP", primary = true },
  ]

  env_vars = [
    for db in local.databases : {
      name   = "DATABASE_URL_${upper(replace(db.instance.name, "-", "_"))}"
      secret = "${var.env_name}/dbaas/postgres/${db.instance.name}/user/${db.user.username}/internal-database-url"
    }
  ]

  expose_to_internet = true
  tags               = ["cigale", "development", "terraform"]
}

resource "hyperfluid_container_app" "redis_studio" {
	env = local.env
	slug = "biodimedia-redis-studio"
	image_repository = "redis/redisinsight"
	image_tag = "latest"
	resource_tier = "nano"
	enabled= true
	replicas = 1

	ports = [
		{ name = "http", port = 5540, protocol = "HTTP", primary = true },
	]

	env_vars = [
		{ name = "REDIS_HOST", value = hyperfluid_managed_redis.redis_studio.host },
		{ name = "REDIS_PORT", value = tostring(hyperfluid_managed_redis.redis_studio.port) },
	]

	health_check_path = "/api/v1/health"
	health_check_port = 5540

	expose_to_internet = true
	tags = ["ecosignal", "development", "terraform"]
}

# ---------------------------------------------------------------------------
# Service links
# ---------------------------------------------------------------------------
# Under the default "lenient" isolation these only record intent; under
# "strict" they are what permits the traffic.

# db-studio browses both application databases.
locals {
  db_studio_db_links = {
    pleye = {
      consumer = hyperfluid_container_app.db_studio.slug
      target   = hyperfluid_managed_postgresql.pleye_db.slug
    }
    beamup = {
      consumer = hyperfluid_container_app.db_studio.slug
      target   = hyperfluid_managed_postgresql.beamup_db.slug
    }
  }
}

resource "hyperfluid_service_link" "db_studio_databases" {
  for_each = local.db_studio_db_links

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
