# AGENTS.md — From-dockerhub-to-AWS-deployment-template

## Commands

| Command | What it does |
|---|---|
| `npm run dev` | Run with `ts-node src/index.ts` (hot reload) |
| `npm run build` | `tsc` → outputs to `dist/` |
| `npm start` | `node dist/index.js` |
| `npm test` | `jest --passWithNoTests` (matches `**/*.test.ts` in `src/`) |
| `npm run lint` | `eslint src/` |
| `npm run typecheck` | `tsc --noEmit` |

CI order (`.github/workflows/ci-cd.yml`): `lint → test → typecheck`. Run in this order locally before pushing.

## Architecture

- Single package, single entrypoint: `src/index.ts` (Express server, port 3000, overridable via `PORT` env)
- Routes: `GET /health` and `GET /`
- All source in `src/`, compiled output in `dist/` (gitignored)
- Only production dependency: `express`

## Docker

- Multi-stage Dockerfile (`node:22-alpine`), runs as non-root `appuser`
- Port 3000, healthcheck: `wget --spider http://localhost:3000/health`
- `docker-compose.yml` reads `DOCKER_HUB_USERNAME` and `DOCKER_HUB_REPO` from env
- `deploy.sh` — manual fallback script to deploy on EC2 directly: `./deploy.sh <docker-image-tag>`

## CI/CD Pipeline

Workflow files (`.github/workflows/`):

| File | Trigger | Purpose |
|---|---|---|
| `ci-cd.yml` | push (develop/staging/main/master) + PRs | test → build → deploy |
| `rollback.yml` | `workflow_dispatch` (manual) | deploy a specific image tag |

**Job flow in `ci-cd.yml`:**
- **test** (all branches/PRs): lint → test → typecheck
- **build-and-push** (develop, staging, main, master only): builds Docker image tagged with `sha-<fullsha>`, `latest`, and branch name; pushes to Docker Hub
- **deploy-dev** (develop branch → `dev` GitHub Environment): SSH → pull SHA-tagged image → run container → health check → auto-rollback on failure
- **deploy-staging** (staging branch → `staging` GitHub Environment): same as dev
- **deploy-prod** (main/master → `production` GitHub Environment): same as dev/staging; requires **manual approval** (configured in GitHub UI)

**Docker tagging:** Primary deployable tag is `sha-<full-commit-sha>` (e.g., `sha-a1b2c3d4...`). `latest` tag also pushed for convenience but CI deploys by SHA.

**Note:** If `DOCKER_HUB_REPO` secret is not set, CI auto-derives it from the GitHub repo name (lowercased).

## Secrets

### Repo-level secrets (GitHub → Settings → Secrets and variables → Actions)
| Secret | Purpose |
|---|---|
| `DOCKER_HUB_USERNAME` | Docker Hub username for login |
| `DOCKER_HUB_TOKEN` | Docker Hub access token (not password) |
| `EC2_HOST` | EC2 public IP or DNS (fallback for legacy single-env) |
| `EC2_USER` | SSH username (e.g., `ubuntu`, `ec2-user`) |
| `EC2_SSH_KEY` | Private SSH key for EC2 access |
| `EC2_PORT` | SSH port (default 22) |

### Environment-level secrets (GitHub → Settings → Environments → each env → Secrets)
Each environment (`dev`, `staging`, `production`) needs its own:
| Secret | Purpose |
|---|---|
| `EC2_HOST` | EC2 host for that environment |
| `EC2_USER` | SSH user for that environment's EC2 |
| `EC2_SSH_KEY` | SSH private key for that environment's EC2 |
| `EC2_PORT` | SSH port (optional, default 22) |

Environment-level secrets override repo-level secrets when that environment's job runs.

## Initial Setup Guide

### 1. AWS EC2 (one instance per environment or one instance with different ports)

Each environment needs an EC2 instance with Docker installed:

```bash
# SSH into each EC2 instance and run:
sudo apt update && sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker ubuntu  # or ec2-user
# Log out and back in for group to take effect
```

Open ports in each EC2 security group: **22** (SSH) and **3000** (app).

### 2. Docker Hub

1. Create an account at hub.docker.com (if needed)
2. Go to Account Settings → Security → New Access Token
3. Save the token — you'll add it as `DOCKER_HUB_TOKEN` in GitHub secrets

### 3. GitHub Environments

Go to repo → **Settings → Environments → Create environment**. Create three:

| Environment | Deploys from branch | Has manual approval? |
|---|---|---|
| `dev` | `develop` | No |
| `staging` | `staging` | No |
| `production` | `main` / `master` | **Yes** — add **Required reviewers** (1+ person) |

For `production`, after creation: click it → **Required reviewers** → add yourself/team.

### 4. GitHub Secrets

**Repo-level secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `DOCKER_HUB_USERNAME` | Your Docker Hub username |
| `DOCKER_HUB_TOKEN` | The access token from step 2 |

**Environment-level secrets** (Settings → Environments → click each env → Secrets):

Each environment needs its own EC2 connection:

| Secret | Value |
|---|---|
| `EC2_HOST` | Public IP or DNS of that env's EC2 |
| `EC2_USER` | `ubuntu` (or `ec2-user` for Amazon Linux) |
| `EC2_SSH_KEY` | Full private key content (including `-----BEGIN...` and `-----END...` lines) |
| `EC2_PORT` | `22` (optional, defaults to 22) |

Environment-level secrets override repo-level ones for that environment's jobs.

### 5. Branches

```bash
git branch develop
git branch staging
git push origin --all
```

### 6. First deploy

Push to `develop` — this triggers the full pipeline: test → build → push → deploy to dev.
Check the action under the repo **Actions** tab.

## Rollback

- **Manual rollback:** Go to Actions → Rollback Deployment → "Run workflow" → select environment + enter image tag (e.g., `sha-a1b2c3d4...`)
- Find available tags on Docker Hub (repo tags page) or via `docker image ls` on EC2
- `rollback.yml` includes its own health check; it also saves the pre-rollback image so you can rollback a rollback

## Security

- `.env` contains live secrets (SSH key, Docker Hub token) — **never commit `.env` files**. Currently `.env` is NOT gitignored safely; verify `.gitignore` includes `.env` and `.env.*` before any commit.
- On PRs, secrets are absent by default in forks; CI skips build/push/deploy on non-main branches
- Production deploys require manual approval via GitHub Environments (see setup below)
