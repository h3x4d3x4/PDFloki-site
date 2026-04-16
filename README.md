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

Self-hosted via Docker on a Hetzner VPS, exposed through Cloudflare Tunnel (`cloudflared`). There is no reverse proxy and no exposed host port -- `cloudflared` and the site container share a Docker network, so the tunnel routes directly to the site container via internal DNS.

### Initial Setup

The cloudflared container must already be running on the VPS, attached to a Docker network (default: `docker_web`). Then:

```
git clone https://github.com/h3x4d3x4/PDFloki-site.git ~/pdfloki
cd ~/pdfloki
mkdir -p releases-data
docker compose up -d --build
```

The site container joins the external `docker_web` network and is reachable from `cloudflared` as `http://pdfloki-site:80`.

### Tunnel Configuration

In the Cloudflare Zero Trust dashboard, add a public hostname entry for the tunnel:

- **Public hostname:** `pdfloki.app`
- **Service:** `http://pdfloki-site:80`

### Future Updates

```
./deploy.sh
```

## Author

[Hexadexa](https://hexadexa.dev)
