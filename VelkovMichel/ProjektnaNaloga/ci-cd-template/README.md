# CI/CD Template (EC2 + RDS)

Ta mapa vsebuje zacetni template za projekt:
- GitHub Actions workflow za avtomatski deploy,
- deploy/migrate/healthcheck/rollback skripte,
- strukturo, ki jo lahko takoj prilagodis tvoji aplikaciji.

## 1) Kaj dobis
- `.github/workflows/deploy-ec2.yml`
- `scripts/deploy_release.sh`
- `scripts/migrate_rds.sh`
- `scripts/healthcheck.sh`
- `scripts/rollback.sh`

## 2) Predpogoji
- EC2 instanca z Apache/PHP aplikacijo
- RDS (MySQL/MariaDB)
- SSH dostop iz GitHub Actions do EC2
- Uporabnik na EC2 ima pravice za `sudo`

## 3) Potrebni GitHub Secrets
Nastavi v repozitoriju (`Settings -> Secrets and variables -> Actions`):
- `EC2_HOST` (public IP ali DNS)
- `EC2_USER` (npr. `ubuntu`)
- `EC2_KEY` (vsebina private key)
- `APP_PATH` (npr. `/var/www/html`)
- `RDS_HOST`
- `RDS_DB`
- `RDS_USER`
- `RDS_PASS`

Opcijsko:
- `APP_URL` (ce ni podan, se uporabi `http://localhost`)

## 4) Prilagoditve pred prvo uporabo
1. V workflow datoteki preveri `APP_SOURCE_DIR`.
2. Preveri, da tvoja aplikacija vsebuje `index.html` in `izpis.php` (ali prilagodi healthcheck).
3. Na EC2 preveri, da je namescen `mariadb-client` (skripta ga poskusi namestiti sama).

## 5) Kako zagnati
1. Commit + push na vejo `main`.
2. Workflow `deploy-ec2` se sprozi samodejno.
3. Ob napaki v health check koraku se sprozi rollback.

## 6) Priporocilo za demo
- Najprej pokazi uspesen deploy.
- Nato namerno uvedi napako in pokazi avtomatski rollback.
