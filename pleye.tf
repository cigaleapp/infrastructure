# Pleye on Hyperfluid (biodimedia environment)
#
# Mirrors the app already running in the "default" environment, plus the
# database that was deleted there but is needed here.
#
#   pleye     -> hyperfluid_container_app
#   pleye-db  -> hyperfluid_managed_postgresql (recreated)
#
#   pleye -> pleye-db -> hyperfluid_service_link
#
# KNOWN GAPS in this provider version (hyperfluid_container_app has only
# scalar attributes - env/secret blocks land in a follow-up):
#   1. No env vars: pleye needs VERSION; set it in the Hyperfluid console
#      after `terraform apply`.
#   2. No secret_refs: pleye references DATABASE_URL (pleye-db internal URL)
#      and MASTER_KEY (secret:pleye-master-key); wire them up in the console.
#
# NOTE on ports: hfctl does not report per-app ports, so the port number below
# is inferred from the app's role. Adjust the `ports` block if pleye listens
# elsewhere.

# ---------------------------------------------------------------------------
# Database (deleted in "default", recreated here)
# ---------------------------------------------------------------------------

resource "hyperfluid_managed_postgresql" "pleye_db" {
  env              = local.env
  name             = "pleye-db"
  database_name    = "pleye"
  engine           = "postgresql"
  version          = "17"
  node_tier        = var.pleye_db_node_tier
  storage_capacity = var.pleye_db_storage_gb
  configuration    = var.postgres_configuration
  description      = "Pleye application database"
  tags             = ["pleye", "terraform"]
}

# The running app connects through a dedicated role.
resource "hyperfluid_managed_postgresql_user" "pleye" {
  managed_postgresql = hyperfluid_managed_postgresql.pleye_db.id
  username           = "pleye"
  permission_level   = "editor"
  description        = "Role used by the pleye app"
}

# ---------------------------------------------------------------------------
# Secret
# ---------------------------------------------------------------------------
# pleye reads MASTER_KEY from a container secret. Recreate it here so the app
# can reference it; the value is write-only and never stored in state.
resource "hyperfluid_secret" "pleye_master_key" {
  count = var.pleye_master_key == "" ? 0 : 1

  name             = "pleye-master-key"
  secret_type      = "plaintext"
  value            = var.pleye_master_key
  value_wo_version = var.secrets_version
  description      = "Pleye MASTER_KEY (encryption key)"
}

# ---------------------------------------------------------------------------
# pleye
#   Needs (console): VERSION, and secret_refs DATABASE_URL (pleye-db) and
#   MASTER_KEY (secret:pleye-master-key).
# ---------------------------------------------------------------------------

resource "hyperfluid_container_app" "pleye" {
  env              = local.env
  slug             = "pleye"
  image_repository = var.pleye_image_repository
  image_tag        = var.pleye_image_tag
  resource_tier    = var.pleye_tier
  enabled          = true
  autoscaling      = var.autoscaling_1_3

  ports = [
    { name = "http", port = 3000, protocol = "HTTP", primary = true },
  ]

  env_vars = [
    { name = "VERSION", value = "hf0" },
    { name = "MASTER_KEY", value = "allacmafusca" },
    { name = "DATABASE_URL", secret = "${var.env_name}/dbaas/postgres/${hyperfluid_managed_postgresql.pleye_db.slug}/user/${hyperfluid_managed_postgresql_user.pleye.username}/internal-database-url" }
  ]


  expose_to_internet = true
  tags               = ["pleye", "developers", "terraform"]
}

# ---------------------------------------------------------------------------
# Service link
# ---------------------------------------------------------------------------
# Under the default "lenient" isolation this only records intent; under
# "strict" it is what permits the traffic.

resource "hyperfluid_service_link" "pleye_db" {
  env = local.env

  consumer = {
    kind = "ContainerApp"
    name = hyperfluid_container_app.pleye.slug
  }

  target = {
    kind = "ManagedPostgreSQL"
    name = hyperfluid_managed_postgresql.pleye_db.slug
  }
}
