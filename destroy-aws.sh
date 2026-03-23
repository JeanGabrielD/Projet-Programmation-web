#!/usr/bin/env bash
# =============================================================================
# destroy-aws.sh — Supprime toutes les ressources AWS créées par deploy-aws.sh
# ⚠  ATTENTION : irréversible, toutes les données seront perdues
# =============================================================================

set -euo pipefail

REGION="eu-west-3"   # doit correspondre à deploy-aws.sh
APP_NAME="sport-tracker"
ENV_NAME="sport-tracker-prod"
DB_INSTANCE="sport-tracker-db"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${RED}⚠  Cette commande va supprimer TOUTES les ressources AWS de SportLog.${NC}"
read -p "Tape 'supprimer' pour confirmer : " CONFIRM
[ "$CONFIRM" = "supprimer" ] || { echo "Annulé."; exit 0; }

# Elastic Beanstalk
echo -e "${YELLOW}Suppression de l'environnement Elastic Beanstalk...${NC}"
cd backend
eb terminate "$ENV_NAME" --force 2>/dev/null || true

# RDS
echo -e "${YELLOW}Suppression de l'instance RDS...${NC}"
aws rds delete-db-instance \
  --db-instance-identifier "$DB_INSTANCE" \
  --skip-final-snapshot \
  --region "$REGION" 2>/dev/null || true

# Lire le bucket depuis deploy-output.txt
if [ -f "../deploy-output.txt" ]; then
  S3_BUCKET=$(grep "S3 Bucket" ../deploy-output.txt | awk '{print $NF}')
  CF_DOMAIN=$(grep "CloudFront" ../deploy-output.txt | awk '{print $NF}' | sed 's|https://||')

  echo -e "${YELLOW}Vidage et suppression du bucket S3 : $S3_BUCKET${NC}"
  aws s3 rm "s3://${S3_BUCKET}" --recursive 2>/dev/null || true
  aws s3api delete-bucket --bucket "$S3_BUCKET" --region "$REGION" 2>/dev/null || true

  echo -e "${YELLOW}Désactivation de la distribution CloudFront...${NC}"
  CF_ID=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?DomainName=='${CF_DOMAIN}'].Id" \
    --output text 2>/dev/null || true)
  if [ -n "$CF_ID" ]; then
    ETAG=$(aws cloudfront get-distribution-config --id "$CF_ID" --query 'ETag' --output text)
    aws cloudfront get-distribution-config --id "$CF_ID" \
      | jq '.DistributionConfig.Enabled = false' \
      | aws cloudfront update-distribution --id "$CF_ID" --if-match "$ETAG" --distribution-config file:///dev/stdin 2>/dev/null || true
    echo "Distribution CloudFront désactivée (la suppression prend ~15 min)."
  fi
fi

echo -e "${GREEN}✅ Suppression lancée. Les ressources RDS/CloudFront peuvent prendre quelques minutes à disparaître.${NC}"
