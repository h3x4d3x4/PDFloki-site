# PDFloki Site — Implementation Guide

Live at **https://pdfloki.app**. Static HTML/CSS served via nginx in Docker on TrueNAS,
exposed through a Cloudflare Tunnel (no reverse proxy).

---

## 1. Architecture

```
GitHub (PDFloki-site repo)
        │  git pull
        ▼
TrueNAS server  /mnt/hexapool/docker/compose/pdfloki/
        │
        ├── Docker container  pdfloki-site  (port 8089)
        │         nginx → /usr/share/nginx/html/
        │
        └── Volume mount  ./releases-data/ → /usr/share/nginx/html/releases/
                (DMGs live here — NOT in git)

Cloudflare Tunnel  pdfloki.app → http://localhost:8089
```

**Why releases are not in git:** DMG files are 70–100 MB each. The Dockerfile's
`COPY releases/` would balloon the image and slow every deploy. Instead, DMGs
are uploaded directly to the server volume by GitHub Actions in the main app repo
and nginx serves them from there.

---

## 2. Current File Structure

```
PDFloki-site/
├── index.html          # Landing page (2 179 lines, self-contained CSS)
├── privacy.html        # Privacy policy
├── icon.png            # App icon (used for favicon + OG image)
├── nginx.conf          # nginx config (appcast + releases routing already set)
├── Dockerfile          # nginx:alpine, copies static files + appcast.xml
├── docker-compose.yaml # Exposes port 8089, pdfloki-network
├── deploy.sh           # git pull → docker compose down/up (runs on server)
├── releases/           # EMPTY in git — placeholder so COPY doesn't error
└── IMPLEMENTATION.md   # This file
```

### Files to add

```
PDFloki-site/
├── changelog.html      # Public-facing version history (generated from CHANGELOG.md)
├── download.html       # Download page — latest DMG + checksum + system requirements
├── appcast.xml         # Committed here after each release (auto-updated by CI)
└── releases/           # Stays empty in git (actual DMGs on server volume)
```

---

## 3. Docker — Switch Releases to a Volume Mount

The current `docker-compose.yaml` bakes everything into the image. Releases need to be
on a persistent volume so GitHub Actions can SCP DMGs directly without rebuilding the image.

### Updated `docker-compose.yaml`

```yaml
services:
  pdfloki-web:
    build: .
    container_name: pdfloki-site
    ports:
      - "8089:80"
    volumes:
      # Persist DMG releases outside the image
      - ./releases-data:/usr/share/nginx/html/releases:ro
    networks:
      - pdfloki-network
    restart: unless-stopped

networks:
  pdfloki-network:
    driver: bridge
```

Create the directory on the server once:

```bash
mkdir -p /mnt/hexapool/docker/compose/pdfloki/releases-data
```

### Updated `Dockerfile`

Remove the `COPY releases/` line — nginx will serve from the mounted volume:

```dockerfile
FROM nginx:alpine

COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html  /usr/share/nginx/html/index.html
COPY privacy.html /usr/share/nginx/html/privacy.html
COPY icon.png    /usr/share/nginx/html/icon.png
COPY changelog.html /usr/share/nginx/html/changelog.html
COPY download.html  /usr/share/nginx/html/download.html

# appcast.xml is committed to the repo and copied here
COPY appcast.xm[l] /usr/share/nginx/html/

RUN chmod -R 755 /usr/share/nginx/html && \
    chown -R nginx:nginx /usr/share/nginx/html

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost/ || exit 1
CMD ["nginx", "-g", "daemon off;"]
```

---

## 4. Deployment Flows

There are two separate deployment paths depending on what changed.

### 4a. Site content changes (HTML, CSS, appcast.xml)

Developer pushes to `main` → GitHub Actions SSHs into the server → `git pull` →
`docker compose up -d --build`.

Trigger in `.github/workflows/deploy.yml` (create this):

```yaml
name: Deploy site

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.DEPLOY_HOST }}
          username: ${{ secrets.DEPLOY_USER }}
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          script: |
            cd /mnt/hexapool/docker/compose/pdfloki
            git pull origin main
            docker compose up -d --build
```

Secrets needed in this repo:
| Secret | Value |
|---|---|
| `DEPLOY_HOST` | TrueNAS IP or hostname |
| `DEPLOY_USER` | SSH user on TrueNAS |
| `DEPLOY_SSH_KEY` | Private key whose public key is in `~/.ssh/authorized_keys` on TrueNAS |

### 4b. New app release (DMG + appcast.xml)

This is triggered by the **main PDFloki app repo** (`h3x4d3x4/PDFloki`), not this repo.
When you push a `v*.*.*` tag, the app's `release.yml` workflow:

1. Builds + notarizes the DMG
2. Signs it with Sparkle
3. Generates `appcast.xml`
4. **SCPs the DMG** to `DEPLOY_USER@DEPLOY_HOST:releases-data/PDFloki-X.X.X.dmg`
5. **SCPs `appcast.xml`** to `DEPLOY_USER@DEPLOY_HOST:/mnt/hexapool/docker/compose/pdfloki/appcast.xml`
6. SSHs in to `git add appcast.xml && git commit && git push` so the site repo stays in sync
7. Runs `docker compose up -d --build` to pick up the new appcast

The SCP paths in `../.github/workflows/release.yml` (the app repo) should be:
```
DMG  →  /mnt/hexapool/docker/compose/pdfloki/releases-data/PDFloki-${VERSION}.dmg
appcast → /mnt/hexapool/docker/compose/pdfloki/appcast.xml
```

Update the deploy step in the app repo's `release.yml`:

```yaml
- name: Deploy to pdfloki.app
  env:
    SSH_PRIVATE_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
    DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
    DEPLOY_USER: ${{ secrets.DEPLOY_USER }}
  run: |
    DMG="macos/build/PDFloki-${VERSION}.dmg"
    REMOTE_BASE="/mnt/hexapool/docker/compose/pdfloki"

    mkdir -p ~/.ssh
    echo "$SSH_PRIVATE_KEY" > ~/.ssh/deploy_key
    chmod 600 ~/.ssh/deploy_key
    ssh-keyscan -H "$DEPLOY_HOST" >> ~/.ssh/known_hosts

    # Upload DMG to the volume mount directory
    scp -i ~/.ssh/deploy_key "$DMG" \
      "${DEPLOY_USER}@${DEPLOY_HOST}:${REMOTE_BASE}/releases-data/PDFloki-${VERSION}.dmg"

    # Upload appcast.xml (nginx serves this from the image, so rebuild needed)
    scp -i ~/.ssh/deploy_key appcast/appcast.xml \
      "${DEPLOY_USER}@${DEPLOY_HOST}:${REMOTE_BASE}/appcast.xml"

    # Rebuild image to pick up new appcast.xml
    ssh -i ~/.ssh/deploy_key "${DEPLOY_USER}@${DEPLOY_HOST}" \
      "cd ${REMOTE_BASE} && git add appcast.xml && git diff --cached --quiet || git commit -m 'chore: appcast v${VERSION}' && git push origin main && docker compose up -d --build"

    rm ~/.ssh/deploy_key
```

---

## 5. Pages to Build

### 5a. `download.html`

Minimal page — just the latest version download.

```
/download
├── "Download for macOS" button → https://pdfloki.app/releases/PDFloki-X.X.X.dmg
├── Version badge (e.g. v1.0.1), file size, SHA-256 checksum
├── System requirements: macOS 14 Sonoma or later, Apple Silicon or Intel
└── Link to changelog.html
```

Keep version/size/checksum in a small `version.json` file updated by CI:

```json
{
  "version": "1.0.1",
  "build": "1714000000",
  "dmg": "https://pdfloki.app/releases/PDFloki-1.0.1.dmg",
  "size_mb": 68.2,
  "sha256": "abc123...",
  "date": "2026-04-14",
  "min_macos": "14.0"
}
```

`download.html` fetches `version.json` at load time with a simple `fetch()` so the HTML
never needs to be rebuilt when a new version ships.

### 5b. `changelog.html`

Human-readable version history. Same visual style as index.html.

Each entry:
- Version + date header
- "What's New" bullet list (same content as the Sparkle appcast `<description>`)
- Badge indicating whether it's a Beta or Stable release

Can be generated from `CHANGELOG.md` in the app repo by the release workflow, or
maintained manually here.

### 5c. `version.json`

Updated by the app repo's `release.yml` alongside `appcast.xml`:

```yaml
- name: Generate version.json
  run: |
    SHA256=$(shasum -a 256 "macos/build/PDFloki-${VERSION}.dmg" | awk '{print $1}')
    SIZE_MB=$(du -m "macos/build/PDFloki-${VERSION}.dmg" | cut -f1)
    cat > version.json << EOF
    {
      "version": "${VERSION}",
      "build": "${BUILD}",
      "dmg": "https://pdfloki.app/releases/PDFloki-${VERSION}.dmg",
      "size_mb": ${SIZE_MB},
      "sha256": "${SHA256}",
      "date": "$(date -u +%Y-%m-%d)",
      "min_macos": "14.0"
    }
    EOF
```

Then SCP `version.json` alongside `appcast.xml` to the server.

---

## 6. LemonSqueezy Integration

### Purchase flow

Add a "Buy" button on `index.html` that opens the LemonSqueezy checkout overlay:

```html
<!-- In <head> -->
<script src="https://app.lemonsqueezy.com/js/lemon.js" defer></script>

<!-- Buy button -->
<a class="btn-buy lemonsqueezy-button"
   href="https://pdfloki.lemonsqueezy.com/buy/YOUR_PRODUCT_ID">
  Buy PDFloki — $XX
</a>
```

LemonSqueezy's JS intercepts clicks on `.lemonsqueezy-button` and opens a modal checkout.
No server-side code needed on pdfloki.app.

### Post-purchase license delivery

LemonSqueezy sends a webhook on `order_created`. You need a small webhook receiver to:
1. Receive the event
2. Generate a license key using `scripts/license-keygen.swift`
3. Email the key to the customer

**Simplest option:** a Cloudflare Worker (free tier). The worker receives the webhook,
calls the license generation script on your server via a private endpoint, and returns 200.

Or configure LemonSqueezy's built-in license key generation (it has a native feature for this)
which removes the need for any custom webhook handling — just enable it in the product settings
and it emails the key automatically.

### License activation endpoint (optional, future)

If you want in-app license activation to verify against LemonSqueezy's API:
`POST https://api.lemonsqueezy.com/v1/licenses/validate`

The app already has a `LicenseService.swift` with Ed25519 offline validation.
LemonSqueezy can be used as the storefront while offline Ed25519 remains the runtime check.

---

## 7. GitHub Secrets Summary

Secrets needed in **this** repo (`PDFloki-site`):

| Secret | Description |
|---|---|
| `DEPLOY_HOST` | TrueNAS hostname or IP |
| `DEPLOY_USER` | SSH username |
| `DEPLOY_SSH_KEY` | SSH private key (add public key to `~/.ssh/authorized_keys` on TrueNAS) |

Secrets needed in the **app** repo (`PDFloki`):

| Secret | Description |
|---|---|
| `DEPLOY_HOST` | same server |
| `DEPLOY_USER` | same user |
| `DEPLOY_SSH_KEY` | same key |
| `APPLE_CERTIFICATE` | base64-encoded `.p12` Developer ID cert |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12` export password |
| `KEYCHAIN_PASSWORD` | random string for CI keychain |
| `APPLE_ID` | your Apple ID |
| `APPLE_APP_PASSWORD` | app-specific password (appleid.apple.com) |
| `APPLE_TEAM_ID` | 10-char team ID from developer.apple.com |
| `SPARKLE_PRIVATE_KEY` | `8sllbI26Q1ftTQ8aOaBqhIe1ZRgjq4Q+d0uzCV1iW+Y=` |

---

## 8. Complete Release Checklist

When you want to ship a new version:

```bash
# From the PDFloki app repo, push a version tag:
git tag v1.0.1 && git push origin v1.0.1
```

This triggers `release.yml` in the app repo which automatically:
- [ ] Bumps `Info.plist` version to match the tag
- [ ] Builds universal .app (arm64 + x86_64)
- [ ] Creates and styles the DMG
- [ ] Notarizes with Apple
- [ ] Signs DMG with Sparkle EdDSA key
- [ ] Generates `appcast.xml` + `version.json`
- [ ] SCPs DMG to `releases-data/` on TrueNAS
- [ ] SCPs `appcast.xml` + `version.json` to site root on TrueNAS
- [ ] Commits `appcast.xml` to this site repo
- [ ] Rebuilds Docker image so nginx serves the new appcast
- [ ] Creates a GitHub Release with the DMG attached as an asset

Beta testers are notified by Sparkle within 1 hour (or on next app launch).

---

## 9. Local Development

```bash
# Preview the site locally
python3 -m http.server 8001
# Open http://localhost:8001

# Test nginx config
docker compose up --build
# Open http://localhost:8089
```

Verify appcast is served correctly:
```bash
curl -I http://localhost:8089/appcast.xml
# Should return Content-Type: application/xml, Cache-Control: no-cache
```

Verify a release download would work:
```bash
# Place a test file in releases-data/ then:
curl -I http://localhost:8089/releases/test.dmg
# Should return Content-Disposition: attachment
```
