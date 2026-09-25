# Dedicated online server for Leigon Ball (runs on Render; see render.yaml).
# Builds straight from this repository, so every push (tools\publish.ps1) redeploys
# the server with the same code players are updated to.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
    && rm -rf /var/lib/apt/lists/* \
    && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp/godot \
    && mv /tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot /tmp/godot.zip

WORKDIR /app
COPY . .
# Import assets once at build time so the server starts quickly.
RUN godot --headless --path /app --import || true

# Render passes the port to listen on in $PORT.
ENV PORT=10000
EXPOSE 10000
CMD ["godot", "--headless", "--path", "/app", "res://scenes/server.tscn"]
