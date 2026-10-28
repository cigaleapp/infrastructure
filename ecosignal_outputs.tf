output "frontend_url" {
  description = "Public endpoint of the web application (empty until the frontend runs)."
  value       = hyperfluid_container_app.frontend.endpoint
}

output "db_write_endpoint" {
  value = hyperfluid_managed_postgresql.db.write_endpoint
}

output "db_write_endpoint_host" {
  value = provider::netparse::parse_url(hyperfluid_managed_postgresql.db.write_endpoint).host
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
