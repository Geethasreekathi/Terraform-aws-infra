resource "aws_ecr_repository" "app" {
  name                 = "${var.environment}-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ssm_parameter" "image_tag" {
  name  = "/${var.environment}/app/image-tag"
  type  = "String"
  value = "latest"

  lifecycle {
    ignore_changes = [value]
  }
}
