#!/usr/bin/env bash
# =============================================================================
# deploy-aws.sh — Déploiement de SportLog sur AWS
# Backend  : Elastic Beanstalk (Docker)
# Base de données : RDS PostgreSQL
# Frontend : S3 + CloudFront
#
# Prérequis :
#   - AWS CLI v2 installé et configuré (aws configure)
#   - EB CLI installé (pip install awsebcli)
#   - Node.js 20+
#   - jq installé (brew install jq / apt install jq)
# =============================================================================

set -euo pipefail

# ── Configuration — À MODIFIER ────────────────────────────────────────────────
APP_NAME="sport-tracker"
ENV_NAME="sport-tracker-prod"
REGION="eu-west-3"           # Paris — changer si besoin
DB_INSTANCE="sport-tracker-db"
DB_NAME="sport_tracker"
DB_USER="sportadmin"
DB_PASSWORD="ThisIsAPassword"
JWT_SECRET="$(openssl rand -hex 32)"
S3_BUCKET="${APP_NAME}-frontend-$(date +%s)"
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
FRONTEND_DIR="$SCRIPT_DIR/frontend"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Vérifications ─────────────────────────────────────────────────────────────
command -v aws  >/dev/null 2>&1 || error "AWS CLI non trouvé. Installe-le : https://aws.amazon.com/cli/"
command -v eb   >/dev/null 2>&1 || error "EB CLI non trouvé. Lance : pip install awsebcli"
command -v node >/dev/null 2>&1 || error "Node.js non trouvé."
command -v jq   >/dev/null 2>&1 || error "jq non trouvé. Lance : brew install jq  ou  apt install jq"

info "Déploiement SportLog sur AWS ($REGION)..."
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 — RDS PostgreSQL
# ══════════════════════════════════════════════════════════════════════════════
info "1/4 — Création de la base de données RDS PostgreSQL..."

# Groupe de sécurité pour RDS
SG_RDS=$(aws ec2 create-security-group \
  --group-name "${APP_NAME}-rds-sg" \
  --description "SportLog RDS Security Group" \
  --region "$REGION" \
  --query 'GroupId' --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${APP_NAME}-rds-sg" \
    --region "$REGION" \
    --query 'SecurityGroups[0].GroupId' --output text)

info "Security group RDS : $SG_RDS"

# Créer l'instance RDS (t3.micro = free tier)
aws rds create-db-instance \
  --db-instance-identifier "$DB_INSTANCE" \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version "16.2" \
  --master-username "$DB_USER" \
  --master-user-password "$DB_PASSWORD" \
  --db-name "$DB_NAME" \
  --allocated-storage 20 \
  --storage-type gp2 \
  --no-multi-az \
  --publicly-accessible \
  --vpc-security-group-ids "$SG_RDS" \
  --backup-retention-period 7 \
  --region "$REGION" \
  --no-deletion-protection 2>/dev/null || warn "Instance RDS déjà existante, on continue."

info "Attente que RDS soit disponible (peut prendre 5-10 min)..."
aws rds wait db-instance-available \
  --db-instance-identifier "$DB_INSTANCE" \
  --region "$REGION"

DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE" \
  --region "$REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_ENDPOINT}:5432/${DB_NAME}"
success "RDS disponible : $DB_ENDPOINT"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 — Elastic Beanstalk (Backend)
# ══════════════════════════════════════════════════════════════════════════════
info "2/4 — Déploiement du backend sur Elastic Beanstalk..."

cd "$BACKEND_DIR"

# Initialiser EB si pas encore fait
if [ ! -d ".elasticbeanstalk" ]; then
  eb init "$APP_NAME" \
    --region "$REGION" \
    --platform "Docker" \
    --no-interactive
fi

# Créer l'environnement ou mettre à jour
if ! eb status "$ENV_NAME" 2>/dev/null | grep -q "Status:"; then
  eb create "$ENV_NAME" \
    --instance-type t3.micro \
    --min-instances 1 \
    --max-instances 2 \
    --region "$REGION" \
    --envvars "NODE_ENV=production,PORT=3001,DATABASE_URL=${DATABASE_URL},JWT_SECRET=${JWT_SECRET}" \
    --single
else
  eb setenv \
    "NODE_ENV=production" \
    "PORT=3001" \
    "DATABASE_URL=${DATABASE_URL}" \
    "JWT_SECRET=${JWT_SECRET}"
  eb deploy "$ENV_NAME"
fi

EB_URL=$(eb status "$ENV_NAME" | grep "CNAME" | awk '{print $2}')
BACKEND_URL="http://${EB_URL}"
success "Backend déployé : $BACKEND_URL"

# Mettre à jour le CORS avec l'URL backend
eb setenv "FRONTEND_URL=PLACEHOLDER" 2>/dev/null || true

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 — S3 + CloudFront (Frontend)
# ══════════════════════════════════════════════════════════════════════════════
info "3/4 — Build et déploiement du frontend..."

cd "$FRONTEND_DIR"

# Build avec l'URL du backend
VITE_API_URL="${BACKEND_URL}/api" npm run build

# Créer le bucket S3
aws s3api create-bucket \
  --bucket "$S3_BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || \
  warn "Bucket déjà existant."

# Activer le site statique
aws s3 website "s3://${S3_BUCKET}" \
  --index-document index.html \
  --error-document index.html

# Politique publique (lecture seule)
aws s3api put-bucket-policy \
  --bucket "$S3_BUCKET" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"PublicReadGetObject\",
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${S3_BUCKET}/*\"
    }]
  }"

# Désactiver le blocage d'accès public
aws s3api put-public-access-block \
  --bucket "$S3_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# Upload des fichiers buildés
aws s3 sync dist/ "s3://${S3_BUCKET}" \
  --delete \
  --cache-control "max-age=31536000,immutable" \
  --exclude "index.html"

aws s3 cp dist/index.html "s3://${S3_BUCKET}/index.html" \
  --cache-control "no-cache,no-store,must-revalidate"

# Créer la distribution CloudFront
CF_DISTRIBUTION=$(aws cloudfront create-distribution \
  --distribution-config "{
    \"CallerReference\": \"${APP_NAME}-$(date +%s)\",
    \"Origins\": {
      \"Quantity\": 1,
      \"Items\": [{
        \"Id\": \"S3-${S3_BUCKET}\",
        \"DomainName\": \"${S3_BUCKET}.s3-website.${REGION}.amazonaws.com\",
        \"CustomOriginConfig\": {
          \"HTTPPort\": 80,
          \"HTTPSPort\": 443,
          \"OriginProtocolPolicy\": \"http-only\"
        }
      }]
    },
    \"DefaultCacheBehavior\": {
      \"TargetOriginId\": \"S3-${S3_BUCKET}\",
      \"ViewerProtocolPolicy\": \"redirect-to-https\",
      \"AllowedMethods\": {\"Quantity\": 2, \"Items\": [\"GET\", \"HEAD\"]},
      \"CachedMethods\": {\"Quantity\": 2, \"Items\": [\"GET\", \"HEAD\"]},
      \"ForwardedValues\": {
        \"QueryString\": false,
        \"Cookies\": {\"Forward\": \"none\"}
      },
      \"MinTTL\": 0,
      \"DefaultTTL\": 86400,
      \"MaxTTL\": 31536000,
      \"Compress\": true
    },
    \"CustomErrorResponses\": {
      \"Quantity\": 1,
      \"Items\": [{
        \"ErrorCode\": 403,
        \"ResponsePagePath\": \"/index.html\",
        \"ResponseCode\": \"200\",
        \"ErrorCachingMinTTL\": 0
      }]
    },
    \"Comment\": \"${APP_NAME} frontend\",
    \"Enabled\": true,
    \"PriceClass\": \"PriceClass_100\",
    \"DefaultRootObject\": \"index.html\"
  }" \
  --query 'Distribution.DomainName' \
  --output text)

FRONTEND_URL="https://${CF_DISTRIBUTION}"
success "Frontend déployé : $FRONTEND_URL"

# ══════════════════════════════════════════════════════════════════════════════
# ÉTAPE 4 — Mise à jour CORS backend avec l'URL CloudFront
# ══════════════════════════════════════════════════════════════════════════════
info "4/4 — Mise à jour du CORS backend avec l'URL CloudFront..."

cd "$BACKEND_DIR"
eb setenv "FRONTEND_URL=${FRONTEND_URL}"

# ══════════════════════════════════════════════════════════════════════════════
# RÉSUMÉ
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Déploiement terminé !${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  🌐 Frontend  : ${BLUE}${FRONTEND_URL}${NC}"
echo -e "  🚀 Backend   : ${BLUE}${BACKEND_URL}${NC}"
echo -e "  🗄  Base      : ${BLUE}${DB_ENDPOINT}${NC}"
echo ""
echo -e "${YELLOW}  ⚠  Note : CloudFront peut prendre 10-15 min à se propager${NC}"
echo ""

# Sauvegarder les infos importantes
cat > "$SCRIPT_DIR/deploy-output.txt" << EOL
=== SportLog AWS Deployment — $(date) ===
Frontend  (CloudFront) : ${FRONTEND_URL}
Backend   (EB)         : ${BACKEND_URL}
Database  (RDS)        : ${DB_ENDPOINT}
S3 Bucket              : ${S3_BUCKET}
JWT Secret             : ${JWT_SECRET}
DATABASE_URL           : ${DATABASE_URL}
EOL

success "Infos sauvegardées dans deploy-output.txt (garde ce fichier en sécurité !)"
