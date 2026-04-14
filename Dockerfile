FROM nginx:alpine

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy static site files
COPY index.html /usr/share/nginx/html/index.html
COPY privacy.html /usr/share/nginx/html/privacy.html
COPY icon.png /usr/share/nginx/html/icon.png

# Optional pages — present after first build
COPY changelog.htm[l] /usr/share/nginx/html/
COPY download.htm[l]  /usr/share/nginx/html/

# appcast.xml and version.json — committed to repo, updated by CI on each release
COPY appcast.xm[l]  /usr/share/nginx/html/
COPY version.jso[n] /usr/share/nginx/html/

# releases/ is a Docker volume mount (see docker-compose.yaml) — not baked into the image

# Set proper permissions
RUN chmod -R 755 /usr/share/nginx/html && \
    chown -R nginx:nginx /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
