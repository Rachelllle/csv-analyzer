resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# 2 subnets PUBLICS (et non 1 public + 1 privé) : RDS exige un subnet group
# couvrant au moins 2 AZ même en single-AZ. Pas de NAT Gateway (~35$/mois)
# ici : l'EC2 vit directement dans un subnet public avec une IP publique et
# une route vers l'IGW, donc elle n'a pas besoin d'un NAT pour sortir vers
# Internet (pull d'images Docker, appels AWS API). RDS partage ce même
# subnet mais reste inaccessible depuis Internet grâce à
# publicly_accessible = false et à son security group (voir sg_rds) : le
# fait que le subnet soit "public" au sens routage ne rend pas RDS public.
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Security group EC2 ---
# 22 restreint à var.my_ip (jamais 0.0.0.0/0) : seule la machine de l'admin
# peut ouvrir une session SSH. 80 ouvert au monde : c'est le port web de
# l'app. Pas d'ALB dans ce budget, donc le trafic HTTP arrive directement
# sur l'EC2, mappé vers le conteneur api:8000 par docker compose.

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-${var.environment}-ec2"
  description = "SSH restreint et HTTP public pour instance applicative"
  vpc_id      = aws_vpc.main.id

ingress {
    description = "SSH pipeline et admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP public"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Tout sortant (pull ECR/S3/SSM, apt, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-sg"
  }
}

# --- Security group RDS ---
# Autorise le port 5432 uniquement depuis le security group de l'EC2 (pas de
# CIDR) : seules les instances portant sg_ec2 peuvent atteindre la base,
# indépendamment de leur IP. C'est plus robuste qu'un CIDR figé si l'EC2
# change d'IP (redémarrage, remplacement...).
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds"
  description = "PostgreSQL accessible uniquement depuis EC2 applicative"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL depuis EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }
}
