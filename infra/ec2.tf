# AMI Amazon Linux 2023 officielle, résolue dynamiquement (pas d'ID en dur
# qui se périmerait ou varierait selon la région).
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = var.key_pair_name
  public_key = var.ssh_public_key
}

# Une seule EC2, sans ASG/Fargate/ALB : c'est tout le budget de calcul de ce
# projet. api, worker et redis tournent dessus via docker compose (voir
# user_data). Placée dans le premier subnet public, avec IP publique.
resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    region             = var.aws_region
    account_id         = data.aws_caller_identity.current.account_id
    api_repo_url       = aws_ecr_repository.api.repository_url
    worker_repo_url    = aws_ecr_repository.worker.repository_url
    ssm_param_name     = aws_ssm_parameter.db_password.name
    db_name            = var.db_name
    db_username        = var.db_username
    db_endpoint        = aws_db_instance.main.address
    s3_bucket          = aws_s3_bucket.uploads.bucket
    log_group_name     = aws_cloudwatch_log_group.app.name
    max_upload_size_mb = var.max_upload_size_mb
    log_level          = var.log_level
  })

  # Redéploie l'instance si le script de démarrage change (nouvelle version
  # d'un repo ECR, nouvel endpoint RDS...), pour rester cohérent avec l'état
  # attendu plutôt que de dériver silencieusement.
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-${var.environment}-app"
  }

  depends_on = [aws_db_instance.main]
}
