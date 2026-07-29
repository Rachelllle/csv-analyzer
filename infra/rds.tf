# Mot de passe généré aléatoirement plutôt qu'écrit en dur : jamais versionné,
# jamais saisi à la main. Stocké dans SSM Parameter Store (ci-dessous) et lu
# par l'EC2 au démarrage via son rôle IAM, pas embarqué en clair dans le
# user_data.
resource "random_password" "db" {
  length  = 24
  special = true
  # Caractères exclus des drivers/URLs de connexion PostgreSQL et des heredocs
  # shell utilisés dans le user_data, pour éviter tout souci d'échappement.
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_ssm_parameter" "db_password" {
  name        = "/${var.project_name}/${var.environment}/db_password"
  description = "Mot de passe RDS PostgreSQL, généré par Terraform"
  type        = "SecureString"
  value       = random_password.db.result
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db"
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-${var.environment}"
  engine         = "postgres"
  engine_version = var.db_engine_version

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Single-AZ (pas de standby en réplication synchrone) : Multi-AZ double
  # environ le coût de l'instance RDS pour un failover automatique. Sur un
  # projet étudiant/démo, une brève indisponibilité en cas de panne d'AZ est
  # acceptable ; ce ne serait pas le bon choix pour une charge de prod réelle.
  multi_az = false

  # Pas d'accès public : seule l'EC2 (via sg_rds -> sg_ec2) peut atteindre la
  # base, même si elle est techniquement dans un subnet "public" au sens
  # routage (voir commentaire dans network.tf).
  publicly_accessible = false

  # skip_final_snapshot = true : pas de snapshot final à la destruction. Sur
  # un projet de démo qu'on détruit/recrée régulièrement (budget étudiant),
  # exiger un snapshot final ralentirait chaque `terraform destroy` et
  # accumulerait des snapshots facturés ; en prod on mettrait false.
  skip_final_snapshot = true

  backup_retention_period = 1
  deletion_protection     = false

  # Les mises à jour mineures (16.x -> 16.y) apportent surtout des correctifs
  # de sécurité et sont appliquées par AWS dans la fenêtre de maintenance,
  # sans intervention manuelle. Cohérent avec engine_version en majeure seule
  # (voir variables.tf) : AWS choisit la dernière mineure à la création, puis
  # la maintient à jour au fil du temps plutôt que de la laisser dériver vers
  # une version retirée du catalogue RDS.
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-${var.environment}-rds"
  }
}
