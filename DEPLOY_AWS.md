# 🚀 Déploiement AWS — SportLog

## Architecture déployée

```
Utilisateur
    │
    ▼
CloudFront (HTTPS, CDN mondial)
    │  frontend Vue.js (fichiers statiques)
    ▼
S3 Bucket
                    ┌──────────────────────┐
Utilisateur ───────►│ Elastic Beanstalk    │
                    │ (Backend Node.js      │
                    │  Docker, t3.micro)    │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │ RDS PostgreSQL        │
                    │ (db.t3.micro, 20 GB)  │
                    └──────────────────────┘
```

## Coût estimé (région eu-west-3 Paris)

| Service | Tier | Prix/mois |
|---|---|---|
| Elastic Beanstalk EC2 t3.micro | Free tier 12 mois | ~0€ → ~15€ |
| RDS db.t3.micro | Free tier 12 mois | ~0€ → ~18€ |
| S3 | < 1 Go | < 0.05€ |
| CloudFront | < 1 To transfert | < 1€ |
| **Total** | | **~1€/mois (free tier) → ~35€/mois** |

---

## Prérequis

### 1. Installer AWS CLI v2
```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install
```

### 2. Installer EB CLI
```bash
pip install awsebcli
```

### 3. Configurer les credentials AWS
```bash
aws configure
# AWS Access Key ID     : [ta clé depuis IAM]
# AWS Secret Access Key : [ton secret depuis IAM]
# Default region name   : eu-west-3
# Default output format : json
```

> Pour créer une clé IAM : AWS Console → IAM → Users → ton utilisateur → Security credentials → Create access key

---

## Déploiement

### Étape 1 — Éditer le script de déploiement

Ouvre `deploy-aws.sh` et modifie les variables en haut du fichier :

```bash
REGION="eu-west-3"          # ta région AWS
DB_PASSWORD="ChangeMe_2024!" # ← CHANGER avec un mot de passe fort
```

Le `JWT_SECRET` est généré automatiquement via `openssl rand`.

### Étape 2 — Lancer le déploiement

```bash
chmod +x deploy-aws.sh
./deploy-aws.sh
```

Le script fait tout automatiquement :
1. Crée l'instance **RDS PostgreSQL** et attend qu'elle soit prête
2. Déploie le **backend** sur Elastic Beanstalk avec les variables d'environnement
3. Builde le **frontend** Vue.js et le pousse sur **S3 + CloudFront**
4. Met à jour le **CORS** du backend avec l'URL CloudFront finale

⏱ Durée totale : environ **15-20 minutes** (RDS + CloudFront sont lents à démarrer)

### Étape 3 — Récupérer les URLs

À la fin du script, les URLs sont affichées et sauvegardées dans `deploy-output.txt` :

```
Frontend  (CloudFront) : https://d1234abcdef.cloudfront.net
Backend   (EB)         : http://sport-tracker-prod.eu-west-3.elasticbeanstalk.com
Database  (RDS)        : sport-tracker-db.xxxx.eu-west-3.rds.amazonaws.com
```

> ⚠️ `deploy-output.txt` contient des secrets — ne le committe pas sur Git !

---

## Mises à jour après déploiement

### Mettre à jour le backend
```bash
cd backend
eb deploy sport-tracker-prod
```

### Mettre à jour le frontend
```bash
cd frontend
VITE_API_URL=https://TON-URL-EB.elasticbeanstalk.com/api npm run build
aws s3 sync dist/ s3://TON-BUCKET --delete
# Invalider le cache CloudFront
aws cloudfront create-invalidation --distribution-id TON-CF-ID --paths "/*"
```

---

## Variables d'environnement backend (Elastic Beanstalk)

Configurables via la console AWS ou la CLI :
```bash
cd backend
eb setenv NOM_VARIABLE=valeur
```

| Variable | Description |
|---|---|
| `DATABASE_URL` | URL complète PostgreSQL |
| `JWT_SECRET` | Clé secrète pour les tokens JWT |
| `FRONTEND_URL` | URL CloudFront (pour le CORS) |
| `PORT` | Port du serveur (3001) |
| `NODE_ENV` | `production` |

---

## Supprimer toutes les ressources

```bash
chmod +x destroy-aws.sh
./destroy-aws.sh
```

---

## Dépannage

**Erreur CORS après déploiement**
→ Vérifie que `FRONTEND_URL` dans EB correspond exactement à l'URL CloudFront (avec `https://`)

**502 Bad Gateway sur EB**
→ `eb logs sport-tracker-prod` pour voir les erreurs Node.js

**Frontend affiche une page blanche**
→ Vérifie que `VITE_API_URL` dans `.env.production` pointe vers le bon backend

**RDS inaccessible depuis EB**
→ Vérifie que le security group RDS autorise le traffic depuis le security group EB sur le port 5432
