# Infrastructure AWS (Terraform)

Une seule EC2 (t3.small) qui fait tourner `api`, `worker` et `redis` via
Docker Compose, une RDS PostgreSQL, un bucket S3 pour les fichiers uploadés,
2 dépôts ECR et le nécessaire IAM/réseau/logs autour. Volontairement sans
ALB, sans Fargate, sans NAT Gateway et sans Multi-AZ : voir les commentaires
dans `network.tf` et `rds.tf` pour le détail des arbitrages coût/robustesse.

## 1. Amorçage du backend Terraform (une seule fois, à la main)

Terraform stocke son état dans un bucket S3 et le verrouille via une table
DynamoDB (voir le bloc `backend "s3"` dans `main.tf`). Ces deux ressources ne
peuvent pas être créées par ce même projet Terraform : il en a besoin dès le
tout premier `terraform init`, avant d'avoir rien déployé (problème
d'amorçage / "chicken-and-egg"). On les crée donc manuellement, une fois,
via l'AWS CLI :

```bash
aws s3api create-bucket \
  --bucket csv-analyzer-tfstate \
  --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1

aws s3api put-bucket-versioning \
  --bucket csv-analyzer-tfstate \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket csv-analyzer-tfstate \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket csv-analyzer-tfstate \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws dynamodb create-table \
  --table-name csv-analyzer-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-1
```

Le nom de bucket `csv-analyzer-tfstate` doit être unique dans **tout AWS**
(espace de nommage global S3) : s'il est déjà pris, en choisir un autre et
mettre à jour `backend.bucket` dans `main.tf` en conséquence.

## 2. Configuration

```bash
cp terraform.tfvars.example terraform.tfvars
# éditer terraform.tfvars : my_ip, ssh_public_key, github_repository au minimum
```

## 3. Déploiement

```bash
terraform init
terraform plan
terraform apply
```

## 4. Après le premier `apply`

- Récupérer les outputs utiles :

  ```bash
  terraform output
  ```

- Configurer dans GitHub (Settings → Secrets and variables → Actions) :
  - `AWS_DEPLOY_ROLE_ARN` = `github_actions_role_arn`
  - `AWS_REGION` = la région utilisée (ex: `eu-west-1`)
  - `ECR_API_REPOSITORY` = `ecr_api_repository_url`
  - `ECR_WORKER_REPOSITORY` = `ecr_worker_repository_url`
  - `EC2_HOST` = `ec2_public_ip`
  - `EC2_SSH_PRIVATE_KEY` = la clé privée correspondant à `ssh_public_key`

- Le premier `docker compose up` lancé par `user_data` échouera à récupérer
  les images `api`/`worker` (les dépôts ECR sont encore vides). C'est normal :
  le premier run du workflow `deploy.yml` sur GitHub Actions les construit,
  les pousse, puis se connecte en SSH pour lancer le déploiement réel.

## Destruction

```bash
terraform destroy
```

Le bucket d'état et la table de verrouillage créés à l'étape 1 ne sont pas
gérés par ce module : ils survivent à un `destroy` (ce qui est voulu, sinon
on perd l'historique d'état). À supprimer à la main si besoin.
