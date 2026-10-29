# infra

Infrastructure as Code for **StackStorm** (Dickwella Fashion Corner ecommerce): Docker, docker-compose, CI/CD workflows and deployment scripts.

Broader project: https://github.com/stackstormproject

## Prerequisites

- Docker Desktop (with Docker Compose)

## Run the local databases

1. `git clone https://github.com/stackstormproject/infra.git` and `cd infra`
2. Copy `.env.example` to `.env`
3. `docker compose up -d`
4. `docker compose ps` should show postgres and redis as healthy
5. `docker compose down` stops them (`docker compose down -v` also deletes the data)

## Deployed application

Staging URL: Configured on VPS (`develop` branch auto-deployment)
Production URL: Configured on VPS (`main` branch auto-deployment)

## Shared CI/CD & Auto-Deployment

Reusable GitHub Actions workflows live in `.github/workflows`:

- `backend-ci.yml`: lint, format check, unit and integration tests, security scan, and auto-deploy to VPS via SSH or webhook.
- `frontend-ci.yml`: lint, format check, build, tests with coverage, security scan, and auto-deploy to VPS via SSH or webhook.

Each code repository (`backend`, `frontend`, `stackstorm-frontend-admin`) calls these workflows via `@v1` with `secrets: inherit`.

### Auto-Deployment Setup via GitHub Actions SSH

When any commit is pushed to `develop` (staging) or `main` (production), GitHub Actions automatically runs tests and deploys the updated service to your Cloud VPS without downtime.

#### Required GitHub Secrets

Configure the following secrets in your GitHub Organization or Repository settings (**Settings -> Secrets and variables -> Actions**):

| Secret Name | Description | Example / Default |
|---|---|---|
| `VPS_HOST` | Public IP or DNS of your VPS / EC2 instance | `54.210.12.34` or `ec2-...amazonaws.com` |
| `VPS_USERNAME` | SSH username | `ubuntu` or `ec2-user` |
| `VPS_SSH_KEY` | Private SSH key (PEM / OpenSSH format) | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `VPS_PORT` | SSH Port (optional, default: 22) | `22` |
| `VPS_DEPLOY_PATH` | Full directory path on VPS where project lives | `/home/ubuntu/stackstorm` |

*(Optional)* For separate Staging and Production servers, prefix with `STAGING_` (e.g. `STAGING_VPS_HOST`) or `PROD_` (e.g. `PROD_VPS_HOST`). Alternatively, if you use a webhook service (like Portainer or webhook daemon), use `STAGING_DEPLOY_HOOK` or `PRODUCTION_DEPLOY_HOOK`.

### Initial Server (VPS) Setup

On your Ubuntu / EC2 instance:

```bash
# 1. Install Docker & Git
sudo apt update && sudo apt install -y git docker.io docker-compose-v2
sudo usermod -aG docker $USER

# 2. Clone the repositories into your deployment folder
mkdir -p /home/ubuntu/stackstorm && cd /home/ubuntu/stackstorm
git clone https://github.com/stackstormproject/infra.git
git clone https://github.com/stackstormproject/backend.git
git clone https://github.com/stackstormproject/frontend.git
git clone https://github.com/stackstormproject/stackstorm-frontend-admin.git

# 3. Configure production environment
cd infra
cp .env.prod.example .env
nano .env  # Fill in production secrets (JWT, DB password, Stripe, etc.)

# 4. Make deployment script executable and run initial deployment
chmod +x deploy.sh
./deploy.sh all main
```

After initial setup, any push to GitHub will automatically trigger tests, build the updated container, run migrations, and reload the service!
