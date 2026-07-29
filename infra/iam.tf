# =========================================================================
# Rôle d'instance EC2 : pull ECR, lecture SSM (mot de passe DB), S3
# limité au bucket applicatif, écriture des logs CloudWatch.
# =========================================================================

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.project_name}-${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# Politique managée AWS : couvre GetAuthorizationToken + le pull d'images
# (BatchGetImage, GetDownloadUrlForLayer...) sans avoir à la réécrire à la main.
resource "aws_iam_role_policy_attachment" "ec2_ecr_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Lecture SSM restreinte au seul paramètre du mot de passe DB de ce projet,
# pas un accès SSM générique.
data "aws_iam_policy_document" "ec2_ssm_read" {
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [aws_ssm_parameter.db_password.arn]
  }
}

resource "aws_iam_role_policy" "ec2_ssm_read" {
  name   = "ssm-read-db-password"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_ssm_read.json
}

# S3 : lecture/écriture limitées au bucket applicatif (pas d'accès S3 global).
data "aws_iam_policy_document" "ec2_s3_uploads" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.uploads.arn]
  }
}

resource "aws_iam_role_policy" "ec2_s3_uploads" {
  name   = "s3-uploads-bucket"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_s3_uploads.json
}

# Écriture des logs des conteneurs (driver awslogs de docker compose) vers
# le seul log group de ce projet.
data "aws_iam_policy_document" "ec2_cloudwatch_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "ec2_cloudwatch_logs" {
  name   = "cloudwatch-logs-write"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_cloudwatch_logs.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# =========================================================================
# OIDC GitHub Actions : le pipeline CI/CD assume ce rôle via un jeton OIDC
# à chaque run, sans clé d'accès AWS stockée en secret GitHub.
# =========================================================================

# Empreinte du certificat récupérée dynamiquement plutôt que codée en dur :
# évite un secret désynchronisé si GitHub fait tourner son certificat TLS.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_github_oidc_provider_arn
}

# Restreint l'assume-role au dépôt et à la branche configurés : n'importe
# quel autre repo/branche GitHub ne peut pas obtenir ce rôle, même en
# connaissant son ARN.
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_oidc_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-${var.environment}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

# Droits minimaux pour construire et pousser les 2 images : login ECR
# (GetAuthorizationToken ne supporte pas de restriction par ressource) +
# push sur les 2 dépôts de ce projet uniquement.
data "aws_iam_policy_document" "github_actions_ecr_push" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [
      aws_ecr_repository.api.arn,
      aws_ecr_repository.worker.arn,
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_ecr_push.json
}
