# --- Général ---

variable "aws_region" {
  description = "Région AWS où déployer toutes les ressources."
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Nom du projet, utilisé comme préfixe de nommage et dans les tags."
  type        = string
  default     = "csv-analyzer"
}

variable "environment" {
  description = "Nom de l'environnement (tag Environment, suffixe de nommage)."
  type        = string
  default     = "prod"
}

# --- Réseau ---

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Blocs CIDR des 2 subnets publics (RDS exige au moins 2 AZ pour son subnet group, même en single-AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "my_ip" {
  description = "Ton IP publique en notation CIDR (ex: \"1.2.3.4/32\"), seule autorisée en SSH (port 22) vers l'EC2."
  type        = string
}

# --- EC2 ---

variable "instance_type" {
  description = "Type d'instance EC2. t3.small : 2 vCPU / 2 Go RAM, suffisant pour api + worker + redis en conteneurs sur un jeu de données de démo."
  type        = string
  default     = "t3.small"
}

variable "ssh_public_key" {
  description = "Contenu de la clé publique SSH (ex: le contenu de ~/.ssh/id_ed25519.pub) importée dans AWS pour se connecter à l'EC2."
  type        = string
}

variable "key_pair_name" {
  description = "Nom de la paire de clés EC2 créée à partir de var.ssh_public_key."
  type        = string
  default     = "csv-analyzer-key"
}

# --- Base de données ---

variable "db_name" {
  description = "Nom de la base PostgreSQL applicative."
  type        = string
  default     = "csv_analyzer"
}

variable "db_username" {
  description = "Utilisateur maître PostgreSQL."
  type        = string
  default     = "csv_analyzer"
}

variable "db_engine_version" {
  description = "Version du moteur PostgreSQL. Majeure seule (\"16\") plutôt qu'une mineure figée : AWS retire régulièrement des mineures de RDS (ex: 16.4 retirée), figer une mineure précise ferait alors casser terraform apply. Avec la majeure seule, AWS choisit la dernière mineure disponible à la création, et auto_minor_version_upgrade (voir rds.tf) la maintient à jour ensuite."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "Classe d'instance RDS. db.t4g.micro (Graviton, burstable) : le plus petit palier éligible free-tier / budget étudiant."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Stockage alloué à RDS, en Go."
  type        = number
  default     = 20
}

# --- Stockage / registre d'images ---

variable "s3_bucket_prefix" {
  description = "Préfixe du bucket S3 (uploads applicatifs). Un suffixe aléatoire est ajouté pour garantir l'unicité globale du nom."
  type        = string
  default     = "csv-analyzer-uploads"
}

variable "ecr_image_retention_count" {
  description = "Nombre d'images conservées par dépôt ECR (lifecycle policy)."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Durée de rétention des logs CloudWatch, en jours."
  type        = number
  default     = 14
}

# --- Application (injectées dans le .env généré sur l'EC2) ---

variable "max_upload_size_mb" {
  description = "Taille max d'upload CSV acceptée par l'API, en Mo."
  type        = number
  default     = 200
}

variable "log_level" {
  description = "Niveau de log de l'API et du worker."
  type        = string
  default     = "INFO"
}

# --- CI/CD (GitHub Actions OIDC) ---

variable "github_repository" {
  description = "Dépôt GitHub autorisé à assumer le rôle de déploiement, au format \"owner/repo\"."
  type        = string
}

variable "github_oidc_branch" {
  description = "Branche autorisée à déclencher le déploiement via le rôle OIDC."
  type        = string
  default     = "main"
}

variable "create_github_oidc_provider" {
  description = "Créer le fournisseur OIDC GitHub Actions. À mettre à false si un autre projet du même compte AWS l'a déjà créé (un seul fournisseur par URL et par compte), et renseigner alors existing_github_oidc_provider_arn."
  type        = bool
  default     = true
}

variable "existing_github_oidc_provider_arn" {
  description = "ARN du fournisseur OIDC GitHub Actions déjà existant, utilisé seulement si create_github_oidc_provider = false."
  type        = string
  default     = ""
}
