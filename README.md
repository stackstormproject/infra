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

Staging URL: to be added when hosting is configured.

## Shared CI/CD

Reusable GitHub Actions workflows live in `.github/workflows`:

- `backend-ci.yml`: lint, format check, unit and integration tests, security scan, deploy
- `frontend-ci.yml`: lint, format check, build, tests with coverage, security scan, deploy

Each code repo keeps a small `ci.yml` that calls these workflows with `@v1` and `secrets: inherit`.

To change a workflow: open a PR here, merge it, then move the `v1` tag.
