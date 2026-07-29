terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Backend S3 + verrou DynamoDB.
  #
  # Problème d'amorçage ("chicken-and-egg") : Terraform ne peut pas créer le
  # bucket/la table qui lui servent à stocker et verrouiller SON PROPRE état,
  # puisqu'il a besoin de ce backend dès le premier `terraform init`. Ces deux
  # ressources sont donc créées UNE FOIS, à la main (ou via un mini-script),
  # AVANT d'utiliser ce module. Voir README.md pour la commande exacte.
  #
  # Adapter le nom du bucket (doit être unique dans tout AWS) et la région
  # avant le premier `terraform init`.
  backend "s3" {
    bucket         = "csv-tfstate-rachel2026"
    key            = "csv-analyzer/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "csv-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Zones de disponibilité disponibles dans la région choisie, plutôt que de
# les coder en dur : le module reste portable si on change var.aws_region.
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
