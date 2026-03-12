# Release and Package Strategy

How artifacts are built, published, and consumed in this project.

## Artifact Types

| Artifact            | Where it lives                 | Consumed by          |
| ------------------- | ------------------------------ | -------------------- |
| Go source (modules) | Git repo                       | `go get` from GitHub |
| Container images    | GHCR (`ghcr.io/aaronroethe/*`) | Kubernetes via Kargo |
| Helm charts         | In-repo (`apps/<app>/chart/`)  | ArgoCD               |

## Versioning Strategy

Two types of builds, two types of tags:

| Activity              | Image tag     | Git tag                    | Kargo picks up? |
| --------------------- | ------------- | -------------------------- | --------------- |
| Push to master (code) | `X.Y.Z-dev.N` | `echo-server/vX.Y.Z-dev.N` | No (prerelease) |
| Manual release cut    | `X.Y.Z`       | `echo-server/vX.Y.Z`       | Yes             |

**Dev builds** happen on every push to master that touches `apps/`. They produce
prerelease tags like `0.2.0-dev.7` (base version + commit count since last
stable release). Kargo's `semverConstraint` ignores prerelease tags by default.

**Stable releases** are cut manually via the Release workflow (Actions → Release →
Run workflow). They produce clean semver tags like `0.2.0` that Kargo picks up
and promotes through dev → staging → prod.

## Why Container Images Only

Go has its own distribution mechanism — `go get` pulls source directly from
git. There is no need to publish Go packages to a registry.

The only artifact we publish to GitHub Packages (GHCR) is **container images**,
because Kubernetes requires OCI images to run workloads.

We do not use:

- **GoReleaser** — adds complexity without payoff since we don't cross-compile
  for end users or distribute CLI tools. Our Dockerfiles handle the build.
  Revisit if we add CLI tools or need multi-arch binary distribution.
- **Go module publishing** — the shared `pkg/cfg` module uses `replace`
  directives for monorepo-local imports, so it's not intended for external
  consumption

We use **GitHub Releases** for stable release cuts — they provide tagged release
notes with changelogs and serve as the trigger for Kargo promotion.

## Image Build and Publish Flow

```
Push to master (app code changes)
  → QA Build: prerelease tag (X.Y.Z-dev.N) → GHCR
  → Kargo ignores (prerelease)

Manual release cut (Actions → Release)
  → Stable tag (X.Y.Z) + GitHub Release → GHCR
  → Kargo detects → auto-promotes dev → staging
  → GH Action opens PR → merge → prod
```

Each app has its own Dockerfile in `apps/<app>/Dockerfile` using a common
pattern:

1. `golang:1.22-alpine` build stage — compiles a static binary
2. `distroless/static-debian12:nonroot` runtime — minimal attack surface

## When to Revisit

Consider adding **GoReleaser** if:

- We build CLI tools that users download directly
- We need `brew install` or similar package manager support
- We want automated multi-arch Docker builds outside of CI
