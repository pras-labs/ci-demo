# --- Stage 1: Build ---
FROM golang:1.25-alpine AS builder

# Set working directory
WORKDIR /app

# Install build dependencies and security patches
RUN apk add --no-cache git ca-certificates && update-ca-certificates

# Leverage Docker cache for dependencies
# Rule: cache dependencies to speed up builds and reduce network calls, improving efficiency and reliability.
COPY go.mod ./
# COPY go.sum ./  # Uncomment if you have dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the binary
# -ldflags="-s -w": Strips debug info to reduce binary size
# CGO_ENABLED=0: Static binary for maximum portability
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o server .

# --- Stage 2: Final Runtime ---
# Using "static" distroless image: no shell, no package manager, highly secure.
# Rule: a minimal base image with only the necessary runtime dependencies to run the application, reducing attack surface and improving security.
# Pin to digest for full reproducibility and supply chain integrity (tag latest-amd64 as reference).
# To update: TOKEN=$(curl -s "https://gcr.io/v2/token?scope=repository:distroless/static-debian12:pull&service=gcr.io" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])"); curl -sI "https://gcr.io/v2/distroless/static-debian12/manifests/latest-amd64" -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json" | grep docker-content-digest
FROM gcr.io/distroless/static-debian12@sha256:340ba156c899ddac5ba57c5188b8e7cd56448eb7ee65b280574465eac2718ad2

WORKDIR /

# Copy only the compiled binary from the builder
COPY --from=builder /app/server /server

# Use a non-root user (Standard in Distroless)
# Rule: least privileged user with UID 65532 (nobody) to run the application
USER 65532:65532

# Expose the application port
EXPOSE 8080

# Healthcheck
# distroless has no shell/curl/wget, so copy a static wget binary from busybox
COPY --from=busybox:musl /bin/wget /wget
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/healthz"]

# Run the binary
ENTRYPOINT ["/server"]
