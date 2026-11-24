[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/pi-web?utm_medium=integration&utm_source=button&utm_campaign=pi-web)

# Pi Web on Railway

One-click [Pi Web](https://github.com/jmfederico/pi-web) for [Railway](https://railway.com): a web interface and runtime for the [Pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) that keeps agent sessions running in real workspaces, with chat, files, git and a terminal in the browser.

- **Version:** Pi Web **1.202611.5** with Pi Coding Agent **1.6.0**, installed from npm at those exact versions. Upstream publishes no prebuilt image, so the [`Dockerfile`](Dockerfile) follows upstream's own `docker/Dockerfile` on pinned bases: `ubuntu:26.04@sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db`, `node:22.22.2-bookworm-slim@sha256:9f6d5975c7dca860947d3915877f85607946403fc55349f39b4bc3688448bb6e` (Node runtime) and `caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0`. Changes from upstream's build: Ubuntu's own `git` and `gh` packages instead of the git-core PPA and a mise `gh@latest` download, and no Docker CLI or Playwright browser libraries (Railway has no Docker socket).
- **Login:** Pi Web has no login of its own and its agent can run shell commands, so Caddy puts HTTP basic auth (user `admin`, generated `PI_WEB_PASSWORD`) in front of everything, including the API and WebSockets. Only `/healthz` is open, for Railway's health check. The container refuses to start without a password of 12+ characters.
- **Model:** set `LLM_API_KEY` (and, for a provider other than OpenAI, `LLM_BASE_URL` and `LLM_MODEL`). On every start the service writes an "OpenAI-compatible" provider into Pi's `models.json` that reads the key from the environment, so the key is never stored on the volume. If you change that provider in the UI, the service leaves it alone. Other providers (Anthropic, Google, ...) can be added from Pi Web's settings.
- **Processes:** Pi Web's session daemon and web/API server (upstream's two Compose services) run in one Railway service, with Caddy in front. If any of the three stops, the container exits 1, so Railway's on-failure restart policy brings it back.
- **Data:** one volume at `/data` holds everything: `HOME` (`/data/home`), Pi Web state (`/data/pi-web`), the Pi agent profile with providers and session history (`/data/pi-agent`), mise tool installs, and the default workspace folder `/data/workspace`.
- **Memory:** about 210 MB at idle; it runs on a 0.5 GB service, where a test `npm install` of a small project also fit. Node heaps and upload limits are sized from the service's memory limit. Give it 1 GB or more if the agent builds or runs heavier code.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `LLM_API_KEY` | required | API key for your model provider, e.g. from https://platform.openai.com/api-keys or https://openrouter.ai/keys. |
| `LLM_BASE_URL` | `https://api.openai.com/v1` | Any OpenAI-compatible API (OpenRouter `https://openrouter.ai/api/v1`, Groq, DeepSeek, a vLLM or Ollama server, ...). |
| `LLM_MODEL` | `gpt-5.4-mini` | Model ID at that provider; the default model for new sessions. Add more with `LLM_EXTRA_MODELS` (comma-separated). |
| `PI_WEB_PASSWORD` | `${{secret(24)}}` | Login password (user `admin`). Find it in the service's Variables tab. |
| `PI_WEB_USERNAME` | `admin` | Login user name. |
| `PORT` | `8080` | Port Caddy listens on (Railway's public domain targets it). |

Optional: `LLM_CONTEXT_WINDOW` (default `128000`), `PI_WEB_MAX_UPLOAD_BYTES` (default: 64 MB, at most memory limit / 8), and any of Pi Web's `PI_WEB_*` [configuration variables](https://pi-web.dev/config).

## After deploy

1. Open the service's public URL and sign in as `admin` with `PI_WEB_PASSWORD`.
2. Add a project: a new folder such as `/data/workspace/my-project`, or clone a repository from Pi Web's terminal into `/data/workspace`.
3. Start a session and give the agent instructions.

## Limits

- Pi Web is single-user. Anyone with the password controls the agent and its shell.
- The agent runs as the unprivileged `pi-web` user, but it can read the container's environment, including `LLM_API_KEY`. Don't add secrets to the service that the agent shouldn't see.
- No Docker socket on Railway: Pi Web's Docker-based extras (`hostexec`, in-app updates of a Docker install) are off. Update by applying the template update instead.
- Tools installed outside `/data` (for example with `apt`) are lost on redeploy. Use mise (`mise use --global node@22`) or the workspace.

## Updates

Railway builds this service from this repo, so a merge to `main` that bumps the pinned versions shows deployers an "update available" notice. Read [`CHANGELOG.md`](CHANGELOG.md) (breaking changes first) before applying it. Data on the volume is kept.
