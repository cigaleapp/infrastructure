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
# Secrets (write-only values; not stored in state)
# ---------------------------------------------------------------------------

resource "hyperfluid_secret" "secret_key" {
  name             = "${var.name_prefix}-secret-key"
  secret_type      = "plaintext"
  value            = var.secret_key
  value_wo_version = var.secrets_version
  description      = "EcoSignal backend SECRET_KEY"
}

resource "hyperfluid_secret" "first_superuser_password" {
  name             = "${var.name_prefix}-first-superuser-password"
  secret_type      = "plaintext"
  value            = var.first_superuser_password
  value_wo_version = var.secrets_version
  description      = "EcoSignal backend FIRST_SUPERUSER_PASSWORD"
}

resource "hyperfluid_secret" "sentry_dsn" {
  count = var.sentry_dsn == "" ? 0 : 1

  name             = "${var.name_prefix}-sentry-dsn"
  secret_type      = "plaintext"
  value            = var.sentry_dsn
  value_wo_version = var.secrets_version
  description      = "EcoSignal SENTRY_DSN"
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
  replicas         = 1

  ports = [
    { name = "amqp", port = 5672, protocol = "TCP" },
    { name = "management", port = 15672, protocol = "HTTP", primary = true },
  ]

  expose_to_internet = false
}

# ---------------------------------------------------------------------------
# Backend (FastAPI / gunicorn)
# ---------------------------------------------------------------------------

resource "hyperfluid_container_app" "backend" {
  env              = local.env
  slug             = "${var.name_prefix}-backend"
  image_repository = var.backend_image_repository
  image_tag        = var.backend_image_tag
  resource_tier    = var.backend_tier
  replicas         = 1
  enabled          = var.app_containers_enabled

  ports = [
    { name = "http", port = 8000, protocol = "HTTP", primary = true },
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
  enabled          = var.app_containers_enabled

  ports = [
    { name = "http", port = 80, protocol = "HTTP", primary = true },
  ]

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
