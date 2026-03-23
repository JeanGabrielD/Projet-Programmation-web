# =============================================================================
# deploy-aws.ps1 — Déploiement de SportLog sur AWS (Windows PowerShell)
# Backend  : Elastic Beanstalk (Docker)
# Base de données : RDS PostgreSQL
# Frontend : S3 + CloudFront
#
# Prérequis :
#   - AWS CLI v2  : https://aws.amazon.com/cli/
#   - EB CLI      : pip install awsebcli
#   - Node.js 20+ : https://nodejs.org/
#   - PowerShell 5.1+ (inclus dans Windows 11)
#
# Lancement :
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\deploy-aws.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

# ── Configuration — À MODIFIER ────────────────────────────────────────────────
$APP_NAME    = "sport-tracker"
$ENV_NAME    = "sport-tracker-prod"
$REGION      = "eu-west-3"
$DB_INSTANCE = "sport-tracker-db"
$DB_NAME     = "sport_tracker"
$DB_USER     = "sportadmin"
$DB_PASSWORD = "ChangeMe_2024!"   # ← CHANGER IMPÉRATIVEMENT
$S3_BUCKET   = "$APP_NAME-frontend-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Générer un JWT secret aléatoire
$bytes = New-Object Byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$JWT_SECRET = [System.BitConverter]::ToString($bytes).Replace("-","").ToLower()
# ──────────────────────────────────────────────────────────────────────────────

$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path
$BACKEND_DIR = Join-Path $SCRIPT_DIR "backend"
$FRONTEND_DIR = Join-Path $SCRIPT_DIR "frontend"

function Write-Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Fail    { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# ── Vérifications ─────────────────────────────────────────────────────────────
Write-Info "Vérification des outils requis..."

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Fail "AWS CLI non trouvé. Télécharge-le ici : https://aws.amazon.com/cli/"
}
if (-not (Get-Command eb -ErrorAction SilentlyContinue)) {
    Write-Fail "EB CLI non trouvé. Lance : pip install awsebcli"
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Fail "Node.js non trouvé. Télécharge-le ici : https://nodejs.org/"
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Fail "npm non trouvé. Réinstalle Node.js depuis https://nodejs.org/"
}

Write-Success "Tous les outils sont disponibles."
Write-Host ""

# Vérifier que AWS est configuré
try {
    aws sts get-caller-identity | Out-Null
} catch {
    Write-Fail "AWS CLI non configuré. Lance 'aws configure' d'abord."
}

Write-Info "Déploiement SportLog sur AWS (région : $REGION)..."
Write-Host ""

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 — RDS PostgreSQL
# ══════════════════════════════════════════════════════════════════════════════
Write-Info "1/4 — Création de la base de données RDS PostgreSQL..."

# Créer un security group pour RDS
$sgExists = aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=$APP_NAME-rds-sg" `
    --region $REGION `
    --query "SecurityGroups[0].GroupId" `
    --output text 2>$null

if ($sgExists -eq "None" -or [string]::IsNullOrEmpty($sgExists)) {
    $SG_RDS = aws ec2 create-security-group `
        --group-name "$APP_NAME-rds-sg" `
        --description "SportLog RDS Security Group" `
        --region $REGION `
        --query "GroupId" `
        --output text
    Write-Info "Security group créé : $SG_RDS"
} else {
    $SG_RDS = $sgExists
    Write-Info "Security group existant : $SG_RDS"
}

# Créer l'instance RDS
$rdsExists = aws rds describe-db-instances `
    --db-instance-identifier $DB_INSTANCE `
    --region $REGION `
    --query "DBInstances[0].DBInstanceStatus" `
    --output text 2>$null

if ($rdsExists -eq "None" -or [string]::IsNullOrEmpty($rdsExists)) {
    Write-Info "Création de l'instance RDS (t3.micro — free tier)..."
    aws rds create-db-instance `
        --db-instance-identifier $DB_INSTANCE `
        --db-instance-class db.t3.micro `
        --engine postgres `
        --engine-version "16.2" `
        --master-username $DB_USER `
        --master-user-password $DB_PASSWORD `
        --db-name $DB_NAME `
        --allocated-storage 20 `
        --storage-type gp2 `
        --no-multi-az `
        --publicly-accessible `
        --vpc-security-group-ids $SG_RDS `
        --backup-retention-period 7 `
        --region $REGION `
        --no-deletion-protection | Out-Null
} else {
    Write-Warn "Instance RDS déjà existante ($rdsExists), on continue."
}

Write-Info "Attente que RDS soit disponible (peut prendre 5-10 min)..."
aws rds wait db-instance-available `
    --db-instance-identifier $DB_INSTANCE `
    --region $REGION

$DB_ENDPOINT = aws rds describe-db-instances `
    --db-instance-identifier $DB_INSTANCE `
    --region $REGION `
    --query "DBInstances[0].Endpoint.Address" `
    --output text

$DATABASE_URL = "postgresql://${DB_USER}:${DB_PASSWORD}@${DB_ENDPOINT}:5432/${DB_NAME}"
Write-Success "RDS disponible : $DB_ENDPOINT"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 — Elastic Beanstalk (Backend)
# ══════════════════════════════════════════════════════════════════════════════
Write-Info "2/4 — Déploiement du backend sur Elastic Beanstalk..."

Set-Location $BACKEND_DIR

# Initialiser EB si pas encore fait
if (-not (Test-Path ".elasticbeanstalk")) {
    eb init $APP_NAME --region $REGION --platform "Docker" --no-interactive
}

# Vérifier si l'environnement existe déjà
$ebStatus = eb status $ENV_NAME 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($ebStatus)) {
    Write-Info "Création de l'environnement Elastic Beanstalk..."
    eb create $ENV_NAME `
        --instance-type t3.micro `
        --min-instances 1 `
        --max-instances 2 `
        --region $REGION `
        --envvars "NODE_ENV=production,PORT=3001,DATABASE_URL=$DATABASE_URL,JWT_SECRET=$JWT_SECRET,FRONTEND_URL=PLACEHOLDER" `
        --single
} else {
    Write-Info "Mise à jour de l'environnement existant..."
    eb setenv `
        "NODE_ENV=production" `
        "PORT=3001" `
        "DATABASE_URL=$DATABASE_URL" `
        "JWT_SECRET=$JWT_SECRET"
    eb deploy $ENV_NAME
}

# Récupérer l'URL du backend
$ebStatusOutput = eb status $ENV_NAME
$EB_CNAME = ($ebStatusOutput | Select-String "CNAME").ToString().Split()[-1].Trim()
$BACKEND_URL = "http://$EB_CNAME"
Write-Success "Backend déployé : $BACKEND_URL"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 — S3 + CloudFront (Frontend)
# ══════════════════════════════════════════════════════════════════════════════
Write-Info "3/4 — Build et déploiement du frontend..."

Set-Location $FRONTEND_DIR

# Build avec l'URL du backend
$env:VITE_API_URL = "$BACKEND_URL/api"
npm run build
if ($LASTEXITCODE -ne 0) { Write-Fail "Échec du build frontend." }

# Créer le bucket S3
Write-Info "Création du bucket S3 : $S3_BUCKET"
aws s3api create-bucket `
    --bucket $S3_BUCKET `
    --region $REGION `
    --create-bucket-configuration LocationConstraint=$REGION | Out-Null

# Désactiver le blocage d'accès public
aws s3api put-public-access-block `
    --bucket $S3_BUCKET `
    --public-access-block-configuration `
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# Configurer le site statique
aws s3 website "s3://$S3_BUCKET" `
    --index-document index.html `
    --error-document index.html

# Politique publique
$policy = @"
{
    "Version": "2012-10-17",
    "Statement": [{
        "Sid": "PublicReadGetObject",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::$S3_BUCKET/*"
    }]
}
"@
$policy | aws s3api put-bucket-policy --bucket $S3_BUCKET --policy file:///dev/stdin

# Upload les fichiers buildés
aws s3 sync dist/ "s3://$S3_BUCKET" `
    --delete `
    --cache-control "max-age=31536000,immutable" `
    --exclude "index.html"

aws s3 cp dist/index.html "s3://$S3_BUCKET/index.html" `
    --cache-control "no-cache,no-store,must-revalidate"

# Créer la distribution CloudFront
Write-Info "Création de la distribution CloudFront..."
$cfConfig = @"
{
    "CallerReference": "$APP_NAME-$(Get-Date -Format 'yyyyMMddHHmmss')",
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "S3-$S3_BUCKET",
            "DomainName": "$S3_BUCKET.s3-website.$REGION.amazonaws.com",
            "CustomOriginConfig": {
                "HTTPPort": 80,
                "HTTPSPort": 443,
                "OriginProtocolPolicy": "http-only"
            }
        }]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-$S3_BUCKET",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]},
        "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]},
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {"Forward": "none"}
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true
    },
    "CustomErrorResponses": {
        "Quantity": 1,
        "Items": [{
            "ErrorCode": 403,
            "ResponsePagePath": "/index.html",
            "ResponseCode": "200",
            "ErrorCachingMinTTL": 0
        }]
    },
    "Comment": "$APP_NAME frontend",
    "Enabled": true,
    "PriceClass": "PriceClass_100",
    "DefaultRootObject": "index.html"
}
"@

$cfConfigFile = Join-Path $env:TEMP "cf-config.json"
$cfConfig | Out-File -FilePath $cfConfigFile -Encoding utf8

$CF_DOMAIN = aws cloudfront create-distribution `
    --distribution-config file://$cfConfigFile `
    --query "Distribution.DomainName" `
    --output text

$FRONTEND_URL = "https://$CF_DOMAIN"
Write-Success "Frontend déployé : $FRONTEND_URL"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 4 — Mise à jour CORS backend avec l'URL CloudFront
# ══════════════════════════════════════════════════════════════════════════════
Write-Info "4/4 — Mise à jour du CORS backend avec l'URL CloudFront..."

Set-Location $BACKEND_DIR
eb setenv "FRONTEND_URL=$FRONTEND_URL"

# ══════════════════════════════════════════════════════════════════════════════
# RÉSUMÉ
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Déploiement terminé !" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Frontend  : $FRONTEND_URL" -ForegroundColor Cyan
Write-Host "  Backend   : $BACKEND_URL" -ForegroundColor Cyan
Write-Host "  Base      : $DB_ENDPOINT" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Note : CloudFront peut prendre 10-15 min a se propager" -ForegroundColor Yellow
Write-Host ""

# Sauvegarder les infos
$output = @"
=== SportLog AWS Deployment — $(Get-Date) ===
Frontend  (CloudFront) : $FRONTEND_URL
Backend   (EB)         : $BACKEND_URL
Database  (RDS)        : $DB_ENDPOINT
S3 Bucket              : $S3_BUCKET
JWT Secret             : $JWT_SECRET
DATABASE_URL           : $DATABASE_URL
"@
$output | Out-File -FilePath (Join-Path $SCRIPT_DIR "deploy-output.txt") -Encoding utf8

Write-Success "Infos sauvegardées dans deploy-output.txt (garde ce fichier en sécurité !)"

Set-Location $SCRIPT_DIR
