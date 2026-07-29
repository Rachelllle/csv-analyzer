# Suffixe aléatoire pour garantir l'unicité globale du nom de bucket, sans
# valeur en dur ni dépendance à un compte/une date précise.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "uploads" {
  bucket = "${var.s3_bucket_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-${var.environment}-uploads"
  }
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Blocage complet de l'accès public : les CSV uploadés sont potentiellement
# sensibles, l'app y accède uniquement via l'API/le worker avec des
# identifiants IAM, jamais par URL publique directe.
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- ECR ---

resource "aws_ecr_repository" "api" {
  name                 = "${var.project_name}-api"
  image_tag_mutability = "MUTABLE" # nécessaire pour pouvoir déplacer le tag "latest" à chaque déploiement

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "worker" {
  name                 = "${var.project_name}-worker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Garde les N images les plus récentes par dépôt, pour ne pas payer du
# stockage ECR indéfiniment sur un projet de démo.
locals {
  ecr_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Garder les ${var.ecr_image_retention_count} images les plus récentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "worker" {
  repository = aws_ecr_repository.worker.name
  policy     = local.ecr_lifecycle_policy
}

# --- CloudWatch Logs ---
# Un seul log group pour api + worker (flux séparés par awslogs-stream dans
# le user_data), suffisant pour un projet de cette taille.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/${var.environment}"
  retention_in_days = var.log_retention_days
}
