# Technology Stack

## Orchestration Layer

| Technology | Role | Notes |
|-----------|------|-------|
| Bash | Every script | `#!/bin/bash` + `set -euo pipefail`; toolpath bootstrap → `source config.sh` → `source functions.sh` → ERR trap |
| Make | Component builds & install | `make -j${NPROC}` |
| Git | Upstream source fetch | `git_clone_update` (shallow by default), `git_checkout` (tag / HEAD / latest-tag) |

## Built-Component Toolchains

| Toolchain | Version source | Components built with it |
|-----------|----------------|--------------------------|
| **Go** | auto-detected from podman `go.mod` (`get_required_go_version`, prefers `toolchain` over `go` directive) | podman, buildah, skopeo, conmon, toolbox, go-md2man, container-libs codegen |
| **Rust** (rustup) | netavark `Cargo.toml` `rust-version` (MSRV) via `get_required_rust_version` | netavark, aardvark-dns, fuse-overlayfs (v2+) |
| **C / autotools** | system GCC | crun, catatonit, pasta, fuse-overlayfs (v1.x) |
| **Meson** | system | toolbox |
| **protoc** | latest GitHub release unless `PROTOC_VERSION` pinned | netavark protobuf codegen |
| **go-md2man** | built from source (Go) | man-page generation for buildah + container config man pages |

## Build Caching (opt-in, default off)

| Layer | Target | Env toggle |
|-------|--------|-----------|
| sccache | Rust | `SCCACHE_ENABLED` |
| ccache | C | `CCACHE_ENABLED` (`COMPILERCHECK=content`) |
| Go build cache | Go | centralized in `config.sh` (`GOCACHE`/`GOMODCACHE`) |
| mold linker | Rust linking | `MOLD_ENABLED` (via `.cargo/config.toml`, avoids `RUSTFLAGS` conflict with sccache `RUSTC_WRAPPER`) |

## Packaging & Repository

| Technology | Role |
|-----------|------|
| **nFPM** (`goreleaser/nfpm/v2` @ v2.45.0) | Renders `packaging/nfpm/*.yaml` + `DESTDIR` staging tree into `.deb` files |
| **envsubst** | Injects detected runtime dependencies (`${DETECTED_DEPENDS}`) and versions into nFPM YAML |
| **objdump / dpkg-query** | `detect_runtime_depends` — direct `DT_NEEDED` sonames → owning packages |
| **reprepro** | Assembles the signed APT repository (9 distributions) |
| **GPG** | Signs `Release` / `InRelease` / `Release.gpg` |
| by-hash re-sign helper | Adds `Acquire-By-Hash` (reprepro lacks native support) and re-signs |

## Hosting, CI & Local Testing

| Technology | Role |
|-----------|------|
| **GitHub Actions** | `.github/workflows/build-packages.yml` — 4-cell distro×arch native build matrix + gated publish |
| **GitHub Pages** | Serves the assembled `repo-output/` (atomic `deploy-pages`) |
| **Lima** | Local Ubuntu VMs (`lima/ubuntu-24.yaml`, `lima/ubuntu-26.yaml`) for on-Ubuntu verification, repo mounted writable |

## Runtime Configuration Shipped

`config/containers.conf` plus containers-common files generated from the
upstream `container-libs` repo (`containers.conf`, `policy.json`,
`registries.conf`, `storage.conf`, `default.yaml`, `seccomp.json`) — packaged
as `podman-container-configs`.
