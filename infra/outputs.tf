output "ec2_public_ip" {
  description = "IP publique de l'instance applicative (accès HTTP et SSH)."
  value       = aws_instance.app.public_ip
}

output "rds_endpoint" {
  description = "Endpoint (host:port) de l'instance RDS PostgreSQL."
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "Adresse (hostname seul, sans port) de l'instance RDS PostgreSQL."
  value       = aws_db_instance.main.address
}

output "ecr_api_repository_url" {
  description = "URL du dépôt ECR de l'image api."
  value       = aws_ecr_repository.api.repository_url
}

output "ecr_worker_repository_url" {
  description = "URL du dépôt ECR de l'image worker."
  value       = aws_ecr_repository.worker.repository_url
}

output "s3_bucket_name" {
  description = "Nom du bucket S3 des fichiers uploadés."
  value       = aws_s3_bucket.uploads.bucket
}

output "github_actions_role_arn" {
  description = "ARN du rôle IAM à renseigner comme secret AWS_DEPLOY_ROLE_ARN dans GitHub Actions."
  value       = aws_iam_role.github_actions.arn
}

output "ssm_db_password_parameter_name" {
  description = "Nom du paramètre SSM SecureString contenant le mot de passe RDS."
  value       = aws_ssm_parameter.db_password.name
}

output "cloudwatch_log_group_name" {
  description = "Nom du log group CloudWatch des conteneurs api/worker."
  value       = aws_cloudwatch_log_group.app.name
}
