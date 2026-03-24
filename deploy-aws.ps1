# =============================================================================
# deploy-aws.ps1 - Deploiement de SportLog sur AWS (Windows PowerShell)
# =============================================================================

$ErrorActionPreference = "Continue"

# -- Configuration - A MODIFIER -----------------------------------------------
$APP_NAME    = "sport-tracker"
$ENV_NAME    = "sport-tracker-prod"
$REGION      = "eu-west-3"
$DB_INSTANCE = "sport-tracker-db"
$DB_NAME     = "sport_tracker"
$DB_USER     = "sportadmin"
$DB_PASSWORD = "ThisIsAPassword"
$S3_BUCKET   = "$APP_NAME-frontend-$(Get-Date -Format 'yyyyMMddHHmmss')"
# -----------------------------------------------------------------------------

$bytes = New-Object Byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$JWT_SECRET = [System.BitConverter]::ToString($bytes).Replace("-","").ToLower()

$SCRIPT_DIR   = Split-Path -Parent $MyInvocation.MyCommand.Path
$BACKEND_DIR  = Join-Path $SCRIPT_DIR "backend"
$FRONTEND_DIR = Join-Path $SCRIPT_DIR "frontend"
$TEMP_DIR     = $env:TEMP

function Write-Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Fail    { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# Appelle une commande AWS en silencant stderr correctement sous Windows
# Retourne stdout, ignore stderr
function Invoke-Aws {
    $result = & aws @args 2>&1
    $stdout = $result | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
    return ($stdout -join "`n").Trim()
}

# Appelle AWS et affiche tout (utile pour les commandes longues comme eb deploy)
function Invoke-AwsVerbose {
    & aws @args
}

function Write-JsonFile {
    param([string]$Path, [object]$Data)
    $json = $Data | ConvertTo-Json -Depth 20
    # Ecriture sans BOM (utf8NoBOM n existe pas en PS 5.1)
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

# -- Verifications -------------------------------------------------------------
Write-Info "Verification des outils requis..."

if (-not (Get-Command aws  -ErrorAction SilentlyContinue)) { Write-Fail "AWS CLI non trouve : https://aws.amazon.com/cli/" }
if (-not (Get-Command eb   -ErrorAction SilentlyContinue)) { Write-Fail "EB CLI non trouve. Lance : pip install awsebcli" }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Write-Fail "Node.js non trouve : https://nodejs.org/" }
if (-not (Get-Command npm  -ErrorAction SilentlyContinue)) { Write-Fail "npm non trouve. Reinstalle Node.js." }

$identity = Invoke-Aws sts get-caller-identity --output json
if (-not $identity -or $identity -notlike "*Account*") {
    Write-Fail "AWS CLI non configure ou credentials invalides. Lance 'aws configure'."
}
Write-Success "AWS connecte : $(($identity | ConvertFrom-Json).Account)"
Write-Host ""
Write-Info "Deploiement SportLog sur AWS (region : $REGION)..."
Write-Host ""

# ==============================================================================
# ETAPE 1 - RDS PostgreSQL
# ==============================================================================
Write-Info "1/4 - Creation de la base de donnees RDS PostgreSQL..."

$sgExists = Invoke-Aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=$APP_NAME-rds-sg" `
    --region $REGION `
    --query "SecurityGroups[0].GroupId" `
    --output text

if ([string]::IsNullOrWhiteSpace($sgExists) -or $sgExists -eq "None") {
    Write-Info "Creation du security group RDS..."
    $SG_RDS = Invoke-Aws ec2 create-security-group `
        --group-name "$APP_NAME-rds-sg" `
        --description "SportLog RDS SG" `
        --region $REGION `
        --query "GroupId" `
        --output text
    if ([string]::IsNullOrWhiteSpace($SG_RDS)) { Write-Fail "Impossible de creer le security group." }
    Write-Info "Security group cree : $SG_RDS"
} else {
    $SG_RDS = $sgExists
    Write-Info "Security group existant : $SG_RDS"
}

$rdsStatus = Invoke-Aws rds describe-db-instances `
    --db-instance-identifier $DB_INSTANCE `
    --region $REGION `
    --query "DBInstances[0].DBInstanceStatus" `
    --output text

if ([string]::IsNullOrWhiteSpace($rdsStatus) -or $rdsStatus -eq "None") {
    Write-Info "Creation de l'instance RDS (db.t3.micro - free tier)..."
    Invoke-Aws rds create-db-instance `
        --db-instance-identifier $DB_INSTANCE `
        --db-instance-class db.t3.micro `
        --engine postgres `
        --engine-version "16.6" `
        --master-username $DB_USER `
        --master-user-password $DB_PASSWORD `
        --db-name $DB_NAME `
        --allocated-storage 20 `
        --storage-type gp2 `
        --no-multi-az `
        --publicly-accessible `
        --vpc-security-group-ids $SG_RDS `
        --backup-retention-period 0 `
        --region $REGION `
        --no-deletion-protection | Out-Null
} else {
    Write-Warn "Instance RDS deja existante (statut : $rdsStatus), on continue."
}

Write-Info "Attente que RDS soit disponible (5-10 min)..."
Invoke-AwsVerbose rds wait db-instance-available `
    --db-instance-identifier $DB_INSTANCE `
    --region $REGION

$DB_ENDPOINT = Invoke-Aws rds describe-db-instances `
    --db-instance-identifier $DB_INSTANCE `
    --region $REGION `
    --query "DBInstances[0].Endpoint.Address" `
    --output text

if ([string]::IsNullOrWhiteSpace($DB_ENDPOINT) -or $DB_ENDPOINT -eq "None") {
    Write-Fail "Impossible de recuperer l'endpoint RDS."
}

$DATABASE_URL = "postgresql://${DB_USER}:${DB_PASSWORD}@${DB_ENDPOINT}:5432/${DB_NAME}"
Write-Success "RDS disponible : $DB_ENDPOINT"

# ==============================================================================
# ETAPE 2 - Elastic Beanstalk (Backend)
# ==============================================================================
Write-Info "2/4 - Deploiement du backend sur Elastic Beanstalk..."

Set-Location $BACKEND_DIR

if (-not (Test-Path ".elasticbeanstalk")) {
    Write-Host ""
    Write-Host "  ACTION REQUISE : eb init non effectue." -ForegroundColor Yellow
    Write-Host "  Depuis le dossier backend/, lance :" -ForegroundColor Yellow
    Write-Host "    eb init sport-tracker --region eu-west-3 --platform Docker" -ForegroundColor White
    Write-Host "  Puis relance .\deploy-aws.ps1 depuis la racine." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$ebCheck = & eb status $ENV_NAME 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Info "Creation de l'environnement Elastic Beanstalk (5-10 min)..."
    $envvars = "NODE_ENV=production,PORT=3001,DATABASE_URL=$DATABASE_URL,JWT_SECRET=$JWT_SECRET,FRONTEND_URL=PLACEHOLDER"
    & eb create $ENV_NAME `
        --instance-type t3.micro `
        --region $REGION `
        --envvars $envvars `
        --single
} else {
    Write-Info "Mise a jour de l'environnement existant..."
    & eb setenv "NODE_ENV=production" "PORT=3001" "DATABASE_URL=$DATABASE_URL" "JWT_SECRET=$JWT_SECRET"
    & eb deploy $ENV_NAME
}

$ebStatus = & eb status $ENV_NAME 2>&1
$EB_CNAME = ($ebStatus | Where-Object { $_ -like "*CNAME*" } | Select-Object -First 1)
if ($EB_CNAME) {
    $EB_CNAME = $EB_CNAME.ToString().Split()[-1].Trim()
} else {
    Write-Fail "Impossible de recuperer le CNAME Elastic Beanstalk."
}
$BACKEND_URL = "http://$EB_CNAME"
Write-Success "Backend deploye : $BACKEND_URL"

# ==============================================================================
# ETAPE 3 - S3 + CloudFront (Frontend)
# ==============================================================================
Write-Info "3/4 - Build et deploiement du frontend..."

Set-Location $FRONTEND_DIR

if (-not (Test-Path "node_modules")) {
    Write-Info "Installation des dependances frontend..."
    & npm install
    if ($LASTEXITCODE -ne 0) { Write-Fail "Echec de npm install." }
}
$env:VITE_API_URL = "$BACKEND_URL/api"
& npm run build
if ($LASTEXITCODE -ne 0) { Write-Fail "Echec du build frontend." }

Write-Info "Creation du bucket S3 : $S3_BUCKET"
Invoke-Aws s3api create-bucket `
    --bucket $S3_BUCKET `
    --region $REGION `
    --create-bucket-configuration LocationConstraint=$REGION | Out-Null

Invoke-Aws s3api put-public-access-block `
    --bucket $S3_BUCKET `
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" | Out-Null

Invoke-Aws s3 website "s3://$S3_BUCKET" `
    --index-document index.html `
    --error-document index.html | Out-Null

$policyObj = [ordered]@{
    Version   = "2012-10-17"
    Statement = @([ordered]@{
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::$S3_BUCKET/*"
    })
}
$policyFile = Join-Path $TEMP_DIR "s3-policy.json"
Write-JsonFile -Path $policyFile -Data $policyObj
Invoke-Aws s3api put-bucket-policy --bucket $S3_BUCKET --policy "file://$policyFile" | Out-Null

Write-Info "Upload du frontend vers S3..."
Invoke-AwsVerbose s3 sync "dist/" "s3://$S3_BUCKET" `
    --delete `
    --cache-control "max-age=31536000,immutable" `
    --exclude "index.html"

Invoke-AwsVerbose s3 cp "dist/index.html" "s3://$S3_BUCKET/index.html" `
    --cache-control "no-cache,no-store,must-revalidate"

Write-Info "Creation de la distribution CloudFront..."
$callerRef = "$APP_NAME-$(Get-Date -Format 'yyyyMMddHHmmss')"
$cfObj = [ordered]@{
    CallerReference = $callerRef
    Origins = [ordered]@{
        Quantity = 1
        Items = @([ordered]@{
            Id         = "S3-$S3_BUCKET"
            DomainName = "$S3_BUCKET.s3-website.$REGION.amazonaws.com"
            CustomOriginConfig = [ordered]@{
                HTTPPort             = 80
                HTTPSPort            = 443
                OriginProtocolPolicy = "http-only"
            }
        })
    }
    DefaultCacheBehavior = [ordered]@{
        TargetOriginId       = "S3-$S3_BUCKET"
        ViewerProtocolPolicy = "redirect-to-https"
        AllowedMethods = [ordered]@{
            Quantity      = 2
            Items         = @("GET","HEAD")
            CachedMethods = [ordered]@{ Quantity = 2; Items = @("GET","HEAD") }
        }
        ForwardedValues = [ordered]@{
            QueryString = $false
            Cookies     = [ordered]@{ Forward = "none" }
        }
        MinTTL     = 0
        DefaultTTL = 86400
        MaxTTL     = 31536000
        Compress   = $true
    }
    CustomErrorResponses = [ordered]@{
        Quantity = 1
        Items = @([ordered]@{
            ErrorCode          = 403
            ResponsePagePath   = "/index.html"
            ResponseCode       = "200"
            ErrorCachingMinTTL = 0
        })
    }
    Comment           = "$APP_NAME frontend"
    Enabled           = $true
    PriceClass        = "PriceClass_100"
    DefaultRootObject = "index.html"
}
$cfConfigFile = Join-Path $TEMP_DIR "cf-config.json"
Write-JsonFile -Path $cfConfigFile -Data $cfObj

# Appel verbeux pour voir l erreur exacte si echec
Write-Info "Contenu du fichier de config CloudFront : $cfConfigFile"
$rawCF = & aws cloudfront create-distribution --distribution-config "file://$cfConfigFile" 2>&1
Write-Host ($rawCF -join "`n")

$CF_DOMAIN = ($rawCF |
    Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
    ForEach-Object { $_ } |
    Out-String |
    ForEach-Object {
        try { ($_ | ConvertFrom-Json).Distribution.DomainName } catch { $null }
    }) | Where-Object { $_ } | Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($CF_DOMAIN) -or $CF_DOMAIN -eq "None") {
    Write-Fail "Impossible de creer la distribution CloudFront. Voir le message ci-dessus."
}

$FRONTEND_URL = "https://$CF_DOMAIN"
Write-Success "Frontend deploye : $FRONTEND_URL"

# ==============================================================================
# ETAPE 4 - Mise a jour CORS backend
# ==============================================================================
Write-Info "4/4 - Mise a jour du CORS backend avec l'URL CloudFront..."
Set-Location $BACKEND_DIR
& eb setenv "FRONTEND_URL=$FRONTEND_URL"

# ==============================================================================
# RESUME
# ==============================================================================
Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  Deploiement termine !" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Frontend  : $FRONTEND_URL" -ForegroundColor Cyan
Write-Host "  Backend   : $BACKEND_URL"  -ForegroundColor Cyan
Write-Host "  Base      : $DB_ENDPOINT"  -ForegroundColor Cyan
Write-Host ""
Write-Host "  Note : CloudFront peut prendre 10-15 min a se propager" -ForegroundColor Yellow
Write-Host ""

@(
    "=== SportLog AWS Deployment - $(Get-Date) ===",
    "Frontend  (CloudFront) : $FRONTEND_URL",
    "Backend   (EB)         : $BACKEND_URL",
    "Database  (RDS)        : $DB_ENDPOINT",
    "S3 Bucket              : $S3_BUCKET",
    "JWT Secret             : $JWT_SECRET",
    "DATABASE_URL           : $DATABASE_URL"
) | Out-File -FilePath (Join-Path $SCRIPT_DIR "deploy-output.txt") -Encoding utf8

Write-Success "Infos sauvegardees dans deploy-output.txt"
Set-Location $SCRIPT_DIR
