# PDFloki Landing Site

Static landing page for [PDFloki](https://github.com/h3x4d3x4/PDFloki) -- a PDF toolkit for macOS. Merge, split, compress, watermark, and manage PDFs. Built with SwiftUI.

The site features a light-themed design with a Norse/Viking motif.

**Live:** [https://pdfloki.app](https://pdfloki.app)

## Tech Stack

- Static HTML/CSS
- Nginx
- Docker

## Local Development

```
python3 -m http.server 8001
```

Then open [http://localhost:8001](http://localhost:8001).

## Deployment

Self-hosted via Docker on TrueNAS, exposed through Cloudflare Tunnel (`cloudflared`). There is no reverse proxy -- `cloudflared` routes traffic directly to the container port.

### Initial Setup

Clone the repository to the TrueNAS compose directory and build:

```
cd /mnt/hexapool/docker/compose/pdfloki/
docker compose up -d --build
```

Serves on port 8089.

### Tunnel Configuration

In the Cloudflare Zero Trust dashboard, add a public hostname entry for the tunnel:

- **Public hostname:** `pdfloki.app`
- **Service:** `http://localhost:8089`

### Future Updates

```
./deploy.sh
```

## Author

[Hexadexa](https://hexadexa.dev)
