# EcoSignal on Hyperfluid
#
# Compose service -> Hyperfluid mapping
#   db            -> hyperfluid_managed_postgresql (engine postgis)
#   geo_db        -> hyperfluid_managed_postgresql (engine postgis, db "geo_db")
#   redis         -> hyperfluid_key_value_cache (Valkey, Redis-compatible)
#   rabbitmq      -> hyperfluid_container_app (rabbitmq:3-management)
#   backend       -> hyperfluid_container_app
#   worker        -> hyperfluid_container_app (queue "interactive")
#   worker-analysis -> hyperfluid_container_app (queue "analysis")
#   frontend      -> hyperfluid_container_app (nginx, internet-facing)
#
# KNOWN GAPS in this provider version (hyperfluid_container_app has only
# scalar attributes - "env/secret/mount blocks land in a follow-up"):
#   1. No env vars: backend/workers need SECRET_KEY, POSTGRES_*, REDIS_*,
#      RABBITMQ_*, GEO_DB_*, FIRST_SUPERUSER* ... (see output backend_env_reference).
#   2. No command override: workers run `python -m app.workers.rabbitmq_worker`,
#      and the two workers differ only by WORKER_QUEUE env + this command.
#   3. No volumes: backend, workers and frontend share /app/sounds (media).
# That is why app_containers_enabled defaults to false.

# ---------------------------------------------------------------------------
# Buckets
# ---------------------------------------------------------------------------
resource "hyperfluid_bucket" "media" {
  env  = local.env
  name = "${var.name_prefix}-media"
}

data "hyperfluid_bucket_credentials" "media" {
  env         = local.env
  bucket_name = hyperfluid_bucket.media.name
}

# ---------------------------------------------------------------------------
# Databases
# ---------------------------------------------------------------------------

resource "hyperfluid_managed_postgresql" "db" {
  env                = local.env
  name               = "${var.name_prefix}-db"
  database_name      = "ecosignal"
  engine             = "postgis"
  version            = "17"
  node_tier          = var.postgres_node_tier
  storage_capacity   = var.postgres_storage_gb
  configuration      = var.postgres_configuration
  expose_to_internet = var.expose_databases_to_internet
  description        = "EcoSignal application database (PostGIS)"
  tags               = ["ecosignal", "terraform"]
}

resource "hyperfluid_managed_postgresql_user" "db_user" {
  username           = "ecosignal"
  managed_postgresql = hyperfluid_managed_postgresql.db.id
  permission_level   = "editor"
}

# NOTE: the compose geo_db image bundles geo_init.sh, which downloads/imports
# reference data on first start. A managed cluster cannot run that script, so
# this creates the empty database; load data afterwards following
# geo_db/GEO_IMPORT_en.md in the repo (set expose_databases_to_internet = true
# temporarily if you import from outside the cluster).
resource "hyperfluid_managed_postgresql" "geo_db" {
  env                = local.env
  name               = "${var.name_prefix}-geo-db"
  database_name      = "geo_db"
  engine             = "postgis"
  version            = "17"
  node_tier          = var.geo_db_node_tier
  storage_capacity   = var.geo_db_storage_gb
  configuration      = var.postgres_configuration
  expose_to_internet = var.expose_databases_to_internet
  description        = "EcoSignal geographical reference database (PostGIS)"
  tags               = ["ecosignal", "terraform"]
}

resource "hyperfluid_managed_postgresql_user" "geo_db_user" {
  username           = "ecosignal"
  managed_postgresql = hyperfluid_managed_postgresql.geo_db.id
  permission_level   = "editor"
}

# ---------------------------------------------------------------------------
# Manual PostGIS engine databases for now
# ---------------------------------------------------------------------------
# Since engine = "postgis" doesn't work yet, see https://discord.com/channels/1190655595724951592/1565079308744134666

# Terraform provider doesnt have persistent volumes yet
# so we just get the existing app
# resource "hyperfluid_container_app" "ecosignal_db_postgis" {
#   env = local.env
#   slug = "${var.name_prefix}-db-postgis"
#   image_repository = "imresamu/postgis"
#   image_tag = "17-3.5"
# }

data "hyperfluid_container_app" "ecosignal_db_postgis" {
  env  = local.env
  slug = "${var.name_prefix}-db-postgis"
}

# ---------------------------------------------------------------------------
# Redis-compatible cache (refresh sessions live only here)
# ---------------------------------------------------------------------------

resource "hyperfluid_key_value_cache" "redis" {
  env              = local.env
  name             = "${var.name_prefix}-cache"
  maxmemory        = "256mb"
  maxmemory_policy = "noeviction" # evicting would silently log users out
  description      = "EcoSignal Redis (refresh sessions, task state)"
  tags             = ["ecosignal", "terraform"]
}

# ---------------------------------------------------------------------------
# RabbitMQ
# ---------------------------------------------------------------------------
# Runs with the image defaults (user/password "ecosignal", vhost "/", same
# defaults docker-compose.yml uses), which is only acceptable because the app is
# not exposed to the internet. There is no volume support yet, so queued
# messages do not survive a restart. Change credentials once env vars land.

resource "hyperfluid_container_app" "rabbitmq" {
  env              = local.env
  slug             = "${var.name_prefix}-rabbitmq"
  image_repository = "rabbitmq"
  image_tag        = "3-management"
  resource_tier    = var.rabbitmq_tier
  autoscaling      = var.autoscaling_1_3

  env_vars = [
    { name = "RABBITMQ_DEFAULT_USER", value = "ecosignal" },
    { name = "RABBITMQ_DEFAULT_PASS", value = "ecosignal" },
    { name = "RABBITMQ_DEFAULT_VHOST", value = "/" },
    { name = "RABBITMQ_ERLANG_COOKIE", value = "ecosignal-erlang-cookie" }
  ]

  ports = [
    { name = "amqp", port = 5672, protocol = "TCP" },
    { name = "management", port = 15672, protocol = "HTTP", primary = true },
  ]

  expose_to_internet = false
}

# ---------------------------------------------------------------------------
# Backend (FastAPI / gunicorn)
# ---------------------------------------------------------------------------

# Custom function to get a secret path for postgresql

locals {
  # Usage: "${db_secret_path_prefix}/<attribute>" where attribute is "internal-host", "internal-port", "password", etc.
  # See https://data-terra.ai.meso.umontpellier.fr/secret-manager/secrets?path=biodimedia%2Fdbaas%2Fpostgres%2Fecosignal-db%2Fuser%2Fecosignal
  secret_path_prefix_db     = "${var.env_name}/dbaas/postgres/${hyperfluid_managed_postgresql.db.slug}/user/${hyperfluid_managed_postgresql_user.db_user.username}"
  secret_path_prefix_geo_db = "${var.env_name}/dbaas/postgres/${hyperfluid_managed_postgresql.geo_db.slug}/user/${hyperfluid_managed_postgresql_user.geo_db_user.username}"

}

resource "hyperfluid_container_app" "backend" {
  env              = local.env
  slug             = "${var.name_prefix}-backend"
  image_repository = var.backend_image_repository
  image_tag        = var.backend_image_tag
  resource_tier    = var.backend_tier
  enabled          = var.app_containers_enabled
  replicas         = 1

  env_vars = [
    # TODO: get from hyperfluid_container_app.frontend.endpoint but we have to remove the https:// in front
    # { name = "DOMAIN", value = "ecosignal-frontend-biodimedia-data-terra.ai.meso.umontpellier.fr" },
    # FIXME: can't do that cuz it creates a cycle since we need the backend to be up for the frontend to start (otherwise ca-ecosignal-backend is "not found" by nginx)
    # { name = "DOMAIN", value = provider::netparse::parse_url(hyperfluid_container_app.frontend.endpoint).host },
    { name = "DOMAIN", value = var.ecosignal_domain },
    { name = "PROJECT_NAME", value = "EcoSignal" },
    # production | staging | local
    { name = "ENVIRONMENT", value = "production" },
    { name = "BACKEND_CORS_ORIGINS", value = "https://${var.ecosignal_domain},https://cigaleapp.github.io,https://${var.cigale_domain}" },
    { name = "SECRET_KEY", secret = "${var.env_name}/${var.secret_path_secret_key}" },
    { name = "FIRST_SUPERUSER", value = "admin" },
    { name = "FIRST_SUPERUSER_PASSWORD", secret = "${var.env_name}/${var.secret_path_first_superuser_password}" },
    # get host part from hyperfluid_managed_postgresql.db.write_endpoint (strip https:// and port)
    # { name = "POSTGRES_SERVER", secret = "${local.secret_path_prefix_db}/internal-host" },
    # # get port part
    # { name = "POSTGRES_PORT", secret = "${local.secret_path_prefix_db}/internal-port" },
    # { name = "POSTGRES_DB", secret = "${local.secret_path_prefix_db}/database" },
    # { name = "POSTGRES_USER", secret = "${local.secret_path_prefix_db}/username" },
    # { name = "POSTGRES_PASSWORD", secret = "${local.secret_path_prefix_db}/password" },
    { name = "POSTGRES_SERVER", value = "ca-${data.hyperfluid_container_app.ecosignal_db_postgis.slug}" },
    { name = "POSTGRES_PORT", value = "5432" },
    { name = "POSTGRES_DB", value = "ecosignal" },
    { name = "POSTGRES_USER", value = "postgres" },
    { name = "POSTGRES_PASSWORD", value = "postgres" },
    { name = "SENTRY_DSN", value = var.sentry_dsn },
    { name = "REDIS_HOST", value = hyperfluid_key_value_cache.redis.host },
    { name = "REDIS_PORT", value = hyperfluid_key_value_cache.redis.port },
    # TODO: check secret path
    { name = "REDIS_PASSWORD", secret = "${var.env_name}/hf-key-value-cache/${hyperfluid_key_value_cache.redis.slug}/password" },
    { name = "REDIS_USER", secret = "${var.env_name}/hf-key-value-cache/${hyperfluid_key_value_cache.redis.slug}/username" },
    # TODO: get rabbitmq's env_vars from the app, not hardcoded
    { name = "RABBITMQ_HOST", value = "ca-${hyperfluid_container_app.rabbitmq.slug}" },
    { name = "RABBITMQ_PORT", value = "5672" },
    { name = "RABBITMQ_USER", value = "ecosignal" },
    { name = "RABBITMQ_PASSWORD", value = "ecosignal" },
    { name = "RABBITMQ_VHOST", value = "/" },
    # { name = "GEO_DB_SERVER", secret = "${local.secret_path_prefix_geo_db}/internal-host" },
    # { name = "GEO_DB_PORT", secret = "${local.secret_path_prefix_geo_db}/internal-port" },
    # { name = "GEO_DB_DB", secret = "${local.secret_path_prefix_geo_db}/database" },
    # { name = "GEO_DB_USER", secret = "${local.secret_path_prefix_geo_db}/username" },
    # { name = "GEO_DB_PASSWORD", secret = "${local.secret_path_prefix_geo_db}/password" },
    { name = "GEO_DB_SERVER", value = "ca-${data.hyperfluid_container_app.ecosignal_db_postgis.slug}" },
    { name = "GEO_DB_PORT", value = "5432" },
    { name = "GEO_DB_DB", value = "geo_db" },
    { name = "GEO_DB_USER", value = "postgres" },
    { name = "GEO_DB_PASSWORD", value = "postgres" },
    # TODO: why?
    { name = "SKIP_PRESTART", value = "false" },
    { name = "MEDIA_S3_MODE", value = "s3" },
    { name = "S3_ENDPOINT", value = data.hyperfluid_bucket_credentials.media.endpoint },
    { name = "S3_ACCESS_KEY", value = data.hyperfluid_bucket_credentials.media.access_key },
    { name = "S3_SECRET_KEY", value = data.hyperfluid_bucket_credentials.media.secret_key },
    { name = "S3_BUCKET", value = data.hyperfluid_bucket_credentials.media.bucket_name },
    # TODO: get dynamically?
    { name = "S3_REGION", value = "default" },
    { name = "MEDIA_CACHE_TTL", value = "300" },
    { name = "LOG_LEVEL", value = "DEBUG" },
    { name = "DB_POOL_SIZE", value = "10" },
    { name = "DB_MAX_OVERFLOW", value = "20" },
    { name = "DB_POOL_TIMEOUT", value = "10" },
    { name = "DB_POOL_RECYCLE", value = "1800" },
  ]

  ports = [
    { name = "http", port = 8000, protocol = "HTTP", primary = true },
  ]

  command = [
    "/bin/sh", "-c",
    replace(
      <<-EOT
		exec gunicorn app.main:app
			-k uvicorn.workers.UvicornWorker
			--bind 0.0.0.0:8000
			--workers "$${WEB_CONCURRENCY:-2}"
			--timeout "$${GUNICORN_TIMEOUT:-120}"
			--graceful-timeout "$${GUNICORN_GRACEFUL_TIMEOUT:-30}"
			--keep-alive "$${GUNICORN_KEEPALIVE:-5}"
			--max-requests "$${GUNICORN_MAX_REQUESTS:-1000}"
			--max-requests-jitter "$${GUNICORN_MAX_REQUESTS_JITTER:-100}"
			--config /app/app/core/gunicorn.py
			--access-logfile -
			--error-logfile -
		EOT
    , "\n", "")
  ]

  # Compose healthcheck is GET /api/v1/health with a 300s start period
  # (migrations + initial data). Make sure the platform probe is equally patient.
  health_check_path = "/api/v1/health"
  health_check_port = 8000

  expose_to_internet = false
}

# ---------------------------------------------------------------------------
# Workers (same image as the backend)
# ---------------------------------------------------------------------------
# Compose runs `python -m app.workers.rabbitmq_worker` with WORKER_QUEUE set to
# "interactive" / "analysis". Neither the command nor the env can be expressed
# yet, so these two are identical until the provider supports them.
# If the platform rejects an app with no port, add a dummy TCP port.

resource "hyperfluid_container_app" "worker" {
  env              = local.env
  slug             = "${var.name_prefix}-worker"
  image_repository = var.backend_image_repository
  image_tag        = var.backend_image_tag
  resource_tier    = var.worker_tier
  replicas         = 1
  enabled          = var.app_containers_enabled

  env_vars = concat(
    hyperfluid_container_app.backend.env_vars,
    [{ name = "WORKER_QUEUE", value = "interactive" }]
  )

  command = ["python", "-m", "app.workers.rabbitmq_worker"]

  expose_to_internet = false
}

resource "hyperfluid_container_app" "worker_analysis" {
  env              = local.env
  slug             = "${var.name_prefix}-worker-analysis"
  image_repository = var.backend_image_repository
  image_tag        = var.backend_image_tag
  resource_tier    = var.worker_tier
  replicas         = 1
  enabled          = var.app_containers_enabled

  env_vars = concat(
    hyperfluid_container_app.backend.env_vars,
    [{ name = "WORKER_QUEUE", value = "analysis" }]
  )

  command = ["python", "-m", "app.workers.rabbitmq_worker"]

  expose_to_internet = false
}

# ---------------------------------------------------------------------------
# Frontend (React build served by nginx) - the only internet-facing service
# ---------------------------------------------------------------------------
# The stock nginx image listens on 80 and the compose file also mounts the media
# volume into it. Confirm nginx's /api proxy target resolves to the backend's
# in-cluster service name on Hyperfluid.

resource "hyperfluid_container_app" "frontend" {
  env              = local.env
  slug             = "${var.name_prefix}-frontend"
  image_repository = var.frontend_image_repository
  image_tag        = var.frontend_image_tag
  resource_tier    = var.frontend_tier
  replicas         = 1
  depends_on       = [hyperfluid_container_app.backend]
  enabled          = var.app_containers_enabled

  ports = [
    { name = "http", port = 80, protocol = "HTTP", primary = true },
  ]

  env_vars = [
    { name = "FRONTEND_PORT", value = "80" },
    # For debug init container
    { name = "ADMINPASS", secret = "${var.env_name}/ecosignal/first-superuser-password" }
  ]

  init_containers = [{
    name             = "debug-backend-communication",
    image_repository = "ghcr.io/cigaleapp/infrastructure/ecosignal-debug",
    image_tag        = "latest",
  }]

  health_check_path = "/"
  health_check_port = 80

  expose_to_internet = true
}

# ---------------------------------------------------------------------------
# Service links
# ---------------------------------------------------------------------------
# Under the default "lenient" isolation these only record intent; under
# "strict" they are what permits the traffic.

locals {
  consumers = {
    backend         = hyperfluid_container_app.backend.slug
    worker          = hyperfluid_container_app.worker.slug
    worker-analysis = hyperfluid_container_app.worker_analysis.slug
  }

  # Targets with a single well-known port (or a single primary port).
  links = {
    backend-db       = { consumer = local.consumers.backend, kind = "ManagedPostgreSQL", target = hyperfluid_managed_postgresql.db.slug }
    backend-geo      = { consumer = local.consumers.backend, kind = "ManagedPostgreSQL", target = hyperfluid_managed_postgresql.geo_db.slug }
    backend-cache    = { consumer = local.consumers.backend, kind = "HfKeyValueCache", target = hyperfluid_key_value_cache.redis.slug }
    worker-db        = { consumer = local.consumers.worker, kind = "ManagedPostgreSQL", target = hyperfluid_managed_postgresql.db.slug }
    worker-geo       = { consumer = local.consumers.worker, kind = "ManagedPostgreSQL", target = hyperfluid_managed_postgresql.geo_db.slug }
    worker-cache     = { consumer = local.consumers.worker, kind = "HfKeyValueCache", target = hyperfluid_key_value_cache.redis.slug }
    analysis-db      = { consumer = local.consumers["worker-analysis"], kind = "ManagedPostgreSQL", target = hyperfluid_managed_postgresql.db.slug }
    analysis-cache   = { consumer = local.consumers["worker-analysis"], kind = "HfKeyValueCache", target = hyperfluid_key_value_cache.redis.slug }
    frontend-backend = { consumer = hyperfluid_container_app.frontend.slug, kind = "ContainerApp", target = hyperfluid_container_app.backend.slug }
  }
}

resource "hyperfluid_service_link" "generic" {
  for_each = local.links

  env = local.env

  consumer = {
    kind = "ContainerApp"
    name = each.value.consumer
  }

  target = {
    kind = each.value.kind
    name = each.value.target
  }
}

# RabbitMQ publishes two ports; only AMQP is needed by the app tier.
resource "hyperfluid_service_link" "amqp" {
  for_each = local.consumers

  env = local.env

  consumer = {
    kind = "ContainerApp"
    name = each.value
  }

  target = {
    kind = "ContainerApp"
    name = hyperfluid_container_app.rabbitmq.slug
  }

  target_ports = [
    { port = 5672, protocol = "TCP" },
  ]
}
