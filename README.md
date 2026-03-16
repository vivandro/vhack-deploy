# vhack-deploy

CLI tool for deploying sites to `*.vhackpad.com`. One command to init a site, one to deploy.

## Install

```bash
curl -sL https://raw.githubusercontent.com/vivandro/vhack-deploy/main/install.sh | bash
```

Or clone manually:
```bash
git clone https://github.com/vivandro/vhack-deploy.git ~/.vhack-deploy
ln -s ~/.vhack-deploy/bin/vhack-deploy /usr/local/bin/vhack-deploy
```

## Usage

```bash
vhack-deploy init my-app              # Create site (nginx, SSL, directories)
vhack-deploy push my-app              # Deploy current directory
vhack-deploy list                     # Show all sites
vhack-deploy rollback my-app          # Revert to previous release
vhack-deploy logs my-app              # Tail logs
vhack-deploy destroy my-app           # Remove everything
vhack-deploy disk                     # Show disk usage
vhack-deploy env my-app edit          # Edit environment variables
```

### Auto-detection

`push` auto-detects your project type:
- **Dockerfile/docker-compose.yml** → builds container, proxies via nginx
- **pubspec.yaml** → runs `flutter build web`, deploys `build/web/`
- **Otherwise** → deploys current directory as static files

## GitHub Actions

Add this to your repo's `.github/workflows/deploy.yml`:

```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: vivandro/vhack-deploy/.github/workflows/deploy.yml@main
    with:
      site: my-app
    secrets:
      DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
```

## Server Setup

Run once on the server:
```bash
sudo bash server-setup.sh
```

This installs vhack-deploy, obtains a wildcard SSL cert, tunes nginx, and migrates existing sites.

## Architecture

- **Symlink-based deploys**: zero-downtime atomic switchover
- **Wildcard SSL**: `*.vhackpad.com`, no per-site certbot
- **3 releases kept** per site for instant rollback
- **JSON registry** at `/opt/vhack-deploy/registry.json`
- **Same activation script** used by both CLI and GitHub Actions
