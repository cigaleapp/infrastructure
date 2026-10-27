output "frontend_url" {
  description = "Public endpoint of the web application (empty until the frontend runs)."
  value       = hyperfluid_container_app.frontend.endpoint
}

output "db_write_endpoint" {
  value = hyperfluid_managed_postgresql.db.write_endpoint
}

output "geo_db_write_endpoint" {
  value = hyperfluid_managed_postgresql.geo_db.write_endpoint
}

output "geo_db_external_endpoint" {
  description = "Only set when expose_databases_to_internet = true; use it to import geo reference data."
  value       = hyperfluid_managed_postgresql.geo_db.external_endpoint
}

output "cache_credentials_secret" {
  description = "Secret holding the Redis connection credentials (reference as secret:<name>)."
  value       = hyperfluid_key_value_cache.redis.credentials_secret_name
}

# Non-secret values the backend/workers need once the provider can inject env.
# Until then, set them in the Hyperfluid console. Endpoint formats (host vs
# host:port) are as reported by the platform - split them if needed.
output "backend_env_reference" {
  value = {
    POSTGRES_SERVER    = hyperfluid_managed_postgresql.db.write_endpoint
    POSTGRES_DB        = "ecosignal"
    GEO_DB_SERVER      = hyperfluid_managed_postgresql.geo_db.write_endpoint
    GEO_DB_NAME        = "geo_db"
    REDIS_HOST         = hyperfluid_key_value_cache.redis.host
    REDIS_PORT         = hyperfluid_key_value_cache.redis.port
    REDIS_PASSWORD     = "from secret:${hyperfluid_key_value_cache.redis.credentials_secret_name}"
    RABBITMQ_HOST      = hyperfluid_container_app.rabbitmq.slug
    RABBITMQ_PORT      = "5672"
    RABBITMQ_USER      = "ecosignal"
    RABBITMQ_PASSWORD  = "ecosignal"
    RABBITMQ_VHOST     = "/"
    SECRET_KEY         = "from secret:${hyperfluid_secret.secret_key.name}"
    FIRST_SUPERUSER_PASSWORD = "from secret:${hyperfluid_secret.first_superuser_password.name}"
    SKIP_PRESTART      = "true"
    WORKER_QUEUE       = "interactive (worker) / analysis (worker-analysis)"
  }
}
