# 5. CI/CD

## 5.1 Pieces

| Piece | What it is |
|---|---|
| Repository | [`kosrodka/dispaces`](https://github.com/kosrodka/dispaces), public. `main` holds released code; `dev` collects merged pull requests. |
| `CLAUDE.md` | Rules for AI coding assistants working on the code (priorities, forbidden APIs, how to build). Changes arrive as pull requests; CI is the judge of whether they build. |
| `ci.yml` | Every push and PR, on GitHub's `macos-26` runner: source guard rails → unit tests → build app → binary security checks → 5-second launch smoke test (also checks for open sockets) → checksum → upload `Dispaces.zip` as a build artifact (kept 14 days). |
| `codeql.yml` | CodeQL static analysis of the Swift code (security-and-quality queries) on pushes to `main`, PRs and weekly. Fails on error-level findings. Results are kept as a SARIF artifact for 30 days. |
| `release.yml` | Push a tag `vX.Y.Z`, or Actions › Release › Run workflow with a version → same checks → GitHub Release with `Dispaces.zip` and its SHA-256. Build provenance attestation runs automatically because the repo is public. |
| `dependabot.yml` | Weekly PRs when a pinned GitHub Action has a new version. The app itself has no dependencies. |

## 5.2 Pipeline hardening

- Every action pinned to a full commit SHA (version in a comment): `actions/checkout` v7.0.1, `actions/upload-artifact` v7.0.2, `github/codeql-action` v4.39.0, `actions/attest-build-provenance` v4.2.2.
- Default `permissions: contents: read`; only the release job can write, and only to releases.
- `persist-credentials: false` on checkout, so later steps can't reuse the token.
- No secrets, no self-hosted runners, no `pull_request_target`.
- The tag is validated (`vX.Y.Z`) before it is used anywhere.

## 5.3 Flow

```
feature branch ──push──▶ CI (build, test, security, smoke) ──▶ PR into dev (CI + CodeQL) ──▶ merge
dev ──PR──▶ main (CI + CodeQL) ──▶ merge
main ──tag v0.1.0──▶ Release (same checks) ──▶ GitHub Release: Dispaces.zip + SHA-256
                                               │
your Mac ◀── download, verify SHA-256 ─────────┘   (or build from source yourself: strongest)
```

## 5.4 Recommended repository settings (set by the owner on GitHub)

1. Settings › Branches › Add rule for `main`: require a pull request, require status checks "Build, test, security checks (macOS 26)" and "analyze".
2. Settings › Actions › General: "Allow kosrodka actions and select non-kosrodka actions" → allow `actions/*` and `github/codeql-action/*` only. Workflow permissions: "Read repository contents".
3. Settings › Code security: turn on Dependabot alerts and secret scanning if offered.

## 5.5 Costs

GitHub-hosted runners, macOS included, are free for public repositories. One CI run is roughly 4–6 minutes; CodeQL roughly 8–10 minutes. CodeQL runs only on `main`, PRs and weekly, not on every branch push.
