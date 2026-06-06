# External Integrations

**Analysis Date:** 2026-03-02

## APIs & External Services

**GitHub:**
- GitHub API - Version detection and source downloads
  - Endpoint: `https://api.github.com/repos/{owner}/{repo}/releases/latest`
  - Usage: Fetching latest tags for Go, Protobuf, and Podman components
  - SDK/Client: curl, git command-line tools

**Go:**
- go.dev - Go version detection
  - Endpoint: `https://go.dev/dl/?mode=json`
  - Usage: Auto-detection of latest Go version
  - SDK/Client: JSON parsing with curl

**Container Registries:**
- Docker Hub - Container image registry
  - Usage: Reference Docker images in test Dockerfiles
  - SDK/Client: Docker CLI (not used in build)

**Protobuf:**
- GitHub Releases - Protocol Buffers distribution
  - Endpoint: GitHub API for protobuf releases
  - Usage: Auto-detection of latest protoc version
  - SDK/Client: curl for JSON API

## Data Storage

**Databases:**
- Not detected - No database integrations

**File Storage:**
- Local filesystem - All builds and binaries installed to `/opt/` and `/usr/local/`

**Caching:**
- XDG_CACHE_HOME - Build cache directory
- GOCACHE - Go build cache

## Authentication & Identity

**Auth Provider:**
- Not detected - No authentication systems in build scripts

**Environment:**
- No auth required for public GitHub repositories

## Monitoring & Observability

**Error Tracking:**
- Custom error handler in functions.sh
- Build logging to timestamped files in `./log/` directory

**Logs:**
- Build progress logging
- Component version tracking
- Error details with script name and line number

## CI/CD & Deployment

**Hosting:**
- Not applicable - Build tool for local installation

**CI Pipeline:**
- Not detected - Manual build process

## Environment Configuration

**Required env vars:**
- `DEBIAN_FRONTEND=noninteractive` - Non-interactive package installation
- `ARCH` - Target architecture (auto-detected)
- `GOPATH` - Go binary path
- `GOROOT` - Go installation path
- `GOCACHE` - Go build cache
- `XDG_CACHE_HOME` - Cache directory
- `HOME` - Home directory (for cloud-init fixes)

**Secrets location:**
- `.mcp.json` - Contains API access token for MetaMCP
  - Token: `sk_mt_...` (escaped in docs)

## Webhooks & Callbacks

**Incoming:**
- Not detected

**Outgoing:**
- HTTP requests to GitHub API
- HTTP requests to go.dev

---

*Integration audit: 2026-03-02*
