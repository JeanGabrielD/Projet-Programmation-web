# =============================================================================
# destroy-aws.ps1 — Supprime toutes les ressources AWS de SportLog
# ATTENTION : irréversible, toutes les données seront perdues
# =============================================================================

$ErrorActionPreference = "Stop"

$REGION      = "eu-west-3"
$APP_NAME    = "sport-tracker"
$ENV_NAME    = "sport-tracker-prod"
$DB_INSTANCE = "sport-tracker-db"
$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "ATTENTION : Cette commande va supprimer TOUTES les ressources AWS de SportLog." -ForegroundColor Red
$confirm = Read-Host "Tape 'supprimer' pour confirmer"
if ($confirm -ne "supprimer") { Write-Host "Annulé."; exit 0 }

# Elastic Beanstalk
Write-Host "Suppression de l'environnement Elastic Beanstalk..." -ForegroundColor Yellow
Set-Location (Join-Path $SCRIPT_DIR "backend")
eb terminate $ENV_NAME --force 2>$null

# RDS
Write-Host "Suppression de l'instance RDS..." -ForegroundColor Yellow
aws rds delete-db-instance `
    --db-instance-identifier $DB_INSTANCE `
    --skip-final-snapshot `
    --region $REGION 2>$null

# S3 + CloudFront depuis deploy-output.txt
$outputFile = Join-Path $SCRIPT_DIR "deploy-output.txt"
if (Test-Path $outputFile) {
    $content = Get-Content $outputFile
    $s3Line = $content | Select-String "S3 Bucket"
    $cfLine  = $content | Select-String "CloudFront"

    if ($s3Line) {
        $S3_BUCKET = $s3Line.ToString().Split(":")[-1].Trim()
        Write-Host "Suppression du bucket S3 : $S3_BUCKET" -ForegroundColor Yellow
        aws s3 rm "s3://$S3_BUCKET" --recursive 2>$null
        aws s3api delete-bucket --bucket $S3_BUCKET --region $REGION 2>$null
    }

    if ($cfLine) {
        $CF_DOMAIN = $cfLine.ToString().Split(":")[-1].Trim().Replace("https://","")
        $CF_ID = aws cloudfront list-distributions `
            --query "DistributionList.Items[?DomainName=='$CF_DOMAIN'].Id" `
            --output text 2>$null
        if ($CF_ID) {
            Write-Host "Désactivation de la distribution CloudFront : $CF_ID" -ForegroundColor Yellow
            Write-Host "La suppression définitive prend ~15 min dans la console AWS." -ForegroundColor Yellow
        }
    }
}

Write-Host "Suppression lancée. Certaines ressources peuvent prendre quelques minutes a disparaitre." -ForegroundColor Green
Set-Location $SCRIPT_DIR
