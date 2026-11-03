# infra

Infrastructure as Code for **StackStorm** (Dickwella Fashion Corner ecommerce): Docker,
docker-compose, CI/CD workflows and deployment scripts.

Broader project: https://github.com/stackstormproject

## Prerequisites

- Docker Desktop (with Docker Compose)

## Run the local databases

1. `git clone https://github.com/stackstormproject/infra.git` and `cd infra`
2. Copy `.env.example` to `.env`
3. `docker compose up -d`
4. `docker compose ps` should show postgres and redis as healthy
5. `docker compose down` stops them (`docker compose down -v` also deletes the data)

## Run the full application locally

From the `infra` directory in this workspace, build and start PostgreSQL, Redis, the API,
the customer storefront, and the admin console:

```powershell
docker compose -f docker-compose.local.yml up --build -d
docker compose -f docker-compose.local.yml ps
docker compose -f docker-compose.local.yml exec backend npm run db:seed
```

The API runs at `http://localhost:5001`, the customer storefront at
`http://localhost:5175`, and the admin console at `http://localhost:5176`. PostgreSQL
and Redis use host ports 5433 and 6380 to avoid conflicts with locally installed services.
The local Compose file supplies development-only credentials; set your own values before
sharing or exposing these services.

To stop the stack, run
`docker compose -f docker-compose.local.yml down`. Add `-v` only if you also want to
delete the local database, Redis, and uploaded-image data.

The production Compose file defaults to the backend folder layout in this workspace.
For separately cloned sibling repositories, set `BACKEND_CONTEXT=../backend` (the
deployment script detects this layout automatically).

## Deployed application

| Environment | Branch | App | URL |
| --- | --- | --- | --- |
| Production | `main` | Customer storefront | https://stackstorm.live/ |
| Production | `main` | Admin console | https://admin.stackstorm.live/ |

Demo staff accounts for signing in to the deployed admin console (seeded data, not real
customer accounts):

| Account | Role | Password |
| --- | --- | --- |
| `admin@stackstorm.lk` | super_admin | `NewPassword123` |
| `support@stackstorm.lk` | support_agent | `NewPassword123` |

## Shared CI/CD & Auto-Deployment

Reusable GitHub Actions workflows live in `.github/workflows`:

- `backend-ci.yml`: lint, format check, unit and integration tests, security scan, and
  auto-deploy to the VPS via SSH or webhook.
- `frontend-ci.yml`: lint, format check, build, tests with coverage, security scan, and
  auto-deploy to the VPS via SSH or webhook.

Each code repository (`backend`, `stackstorm-frontend-customer`, `stackstorm-frontend-admin`)
calls these workflows via `@v1` with `secrets: inherit`.

To change a shared workflow: open a PR here, merge it, then move the `v1` tag.

### Auto-deployment via GitHub Actions SSH

When a commit is pushed to `develop` (staging) or `main` (production), GitHub Actions runs the
tests and deploys the updated service to the VPS with no downtime.

#### Required GitHub secrets

Configure these in the GitHub organization or repository settings
(**Settings → Secrets and variables → Actions**):

| Secret name | Description | Example / default |
| --- | --- | --- |
| `VPS_HOST` | Public IP or DNS of the VPS / EC2 instance | `54.210.12.34` or `ec2-...amazonaws.com` |
| `VPS_USERNAME` | SSH username | `ubuntu` or `ec2-user` |
| `VPS_SSH_KEY` | Private SSH key (PEM / OpenSSH format) | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `VPS_SSH_PORT` | SSH port (optional, default: 22) | `22` |
| `VPS_DEPLOY_PATH` | Full directory path on the VPS where the project lives | `/home/ubuntu/stackstorm` |

For separate staging and production servers, prefix with `STAGING_` (e.g. `STAGING_VPS_HOST`)
or `PROD_` (e.g. `PROD_VPS_HOST`). If using a webhook service (Portainer, a webhook daemon),
use `STAGING_DEPLOY_HOOK` or `PRODUCTION_DEPLOY_HOOK` instead.

#### Initial server (VPS) setup

On the Ubuntu / EC2 instance:

```bash
# 1. Install Docker & Git
sudo apt update && sudo apt install -y git docker.io docker-compose-v2
sudo usermod -aG docker $USER

# 2. Clone the repositories into the deployment folder
mkdir -p /home/ubuntu/stackstorm && cd /home/ubuntu/stackstorm
git clone https://github.com/stackstormproject/infra.git
git clone https://github.com/stackstormproject/backend.git
git clone https://github.com/stackstormproject/stackstorm-frontend-customer.git
git clone https://github.com/stackstormproject/stackstorm-frontend-admin.git

# 3. Configure production environment
cd infra
cp .env.prod.example .env
nano .env  # fill in production secrets (JWT, DB password, Stripe, etc.)

# 4. Make the deployment script executable and run the initial deployment
chmod +x deploy.sh
./deploy.sh all main
```

After this initial setup, any push to GitHub automatically triggers tests, builds the updated
container, runs migrations, and reloads the service.
