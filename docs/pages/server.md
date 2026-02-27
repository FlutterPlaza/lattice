# Server Setup

The Lattice key distribution server is a lightweight HTTP server built on the Dart [shelf](https://pub.dev/packages/shelf) framework. It stores user registrations, pre-key bundles, and pending key-exchange messages. The server never sees or logs cryptographic secrets -- it only stores and relays opaque base64-encoded blobs.

## Architecture

```
                          +-------------------+
    Clients (HTTP) ------>|   Middleware       |
                          |  - Error handler  |
                          |  - Logging        |
                          |  - CORS           |
                          +--------+----------+
                                   |
                          +--------v----------+
                          |   Routes          |
                          |  /api/v1/register |
                          |  /api/v1/prekeys  |
                          |  /api/v1/messages |
                          |  /api/v1/health   |
                          |  /api/v1/metrics  |
                          +--------+----------+
                                   |
                          +--------v----------+
                          |   Storage Backend |
                          |  - InMemoryStorage|
                          |  - FileStorage    |
                          +-------------------+
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/register` | Register a user with their long-term public key |
| `POST` | `/api/v1/prekeys` | Upload a signed pre-key bundle |
| `GET` | `/api/v1/prekeys/:userId` | Fetch and consume a user's pre-key bundle |
| `POST` | `/api/v1/messages/:userId` | Send a key-exchange message to a user |
| `GET` | `/api/v1/messages/:userId` | Fetch and clear pending messages for a user |
| `GET` | `/api/v1/health` | Health check with uptime and version |
| `GET` | `/api/v1/metrics` | Operational metrics (user count, pre-key count, pending messages) |

## Running the Server

### Basic usage

```bash
dart run packages/lattice_server/bin/server.dart
```

The server starts on `localhost:8080` by default.

### Command-line options

```bash
dart run packages/lattice_server/bin/server.dart --help
```

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--port` | `-p` | `8080` | Port to listen on |
| `--host` | `-H` | `localhost` | Host address to bind to |
| `--storage-path` | | *(in-memory)* | Path for file-based persistent storage |
| `--help` | | | Show usage information |

### Examples

```bash
# Listen on all interfaces, port 3000
dart run packages/lattice_server/bin/server.dart --host 0.0.0.0 --port 3000

# Use file-based persistent storage
dart run packages/lattice_server/bin/server.dart --storage-path ./data

# Production-like setup
dart run packages/lattice_server/bin/server.dart \
  --host 0.0.0.0 \
  --port 443 \
  --storage-path /var/lib/lattice
```

## Storage Backends

### InMemoryStorage (default)

All data is stored in Dart `Map` objects and lost when the process exits. Suitable for development and testing.

### FileStorage

Persists data as JSON files in a specified directory:

```
<storage-path>/
  users.json        User registrations
  prekeys.json      Pre-key bundles
  messages.json     Pending key-exchange messages
```

Enable with the `--storage-path` flag:

```bash
dart run packages/lattice_server/bin/server.dart --storage-path ./data
```

FileStorage creates the directory automatically if it does not exist. This backend is suitable for single-instance production deployments.

## Middleware

The server applies three middleware layers in order:

1. **Error Handler** -- catches exceptions and returns proper JSON error responses. `FormatException` maps to 400, `StateError` maps to 409, and all other exceptions map to 500 (without leaking internal details).

2. **Logging** -- logs each request as `TIMESTAMP METHOD PATH -> STATUS (duration)`. Request and response bodies are **never** logged to avoid exposing cryptographic material.

3. **CORS** -- allows cross-origin requests with `Access-Control-Allow-Origin: *`. Handles OPTIONS preflight requests.

Additional middleware is available but not enabled by default:

- **authToken** -- checks for a Bearer token in the Authorization header. Currently a placeholder that accepts any non-empty token.
- **rateLimit** -- per-IP rate limiting (100 requests per minute by default).

## Docker Deployment

The server includes a multi-stage Dockerfile:

```dockerfile
FROM dart:stable AS build
WORKDIR /app
COPY . .
RUN dart pub get
RUN dart compile exe packages/lattice_server/bin/server.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
EXPOSE 8080
ENTRYPOINT ["/app/server"]
```

Build and run:

```bash
# Build the image
docker build -t lattice-server -f packages/lattice_server/Dockerfile .

# Run with in-memory storage
docker run -p 8080:8080 lattice-server --host 0.0.0.0

# Run with persistent storage
docker run -p 8080:8080 -v $(pwd)/data:/data \
  lattice-server --host 0.0.0.0 --storage-path /data
```

## TLS Setup

For production deployments, TLS should be terminated at a reverse proxy (such as nginx, Caddy, or a cloud load balancer) rather than in the Dart process. Example nginx configuration:

```nginx
server {
    listen 443 ssl;
    server_name lattice.example.com;

    ssl_certificate     /etc/ssl/certs/lattice.pem;
    ssl_certificate_key /etc/ssl/private/lattice.key;
    ssl_protocols       TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Graceful Shutdown

The server handles `SIGINT` (Ctrl-C) for graceful shutdown, closing the HTTP listener before exiting. In-memory data is lost on shutdown; use FileStorage for persistence.
