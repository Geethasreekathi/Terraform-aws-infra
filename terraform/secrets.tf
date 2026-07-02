resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#%^*()-_+"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.environment}/app/db-credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = var.db_name
  })
}
