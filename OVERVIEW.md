# Deploy and Host Pi Web on Railway

Pi Web is an open-source (MIT) web interface and runtime for the Pi coding agent. It keeps agent sessions running in real workspaces on a server, so you can give instructions, browse and edit files, use a terminal and review the agent's work from any browser, including a phone, and come back later.

## About Hosting Pi Web

Pi Web runs two Node.js processes: a session daemon that owns the agent sessions and a web/API server. It has no login of its own, and the agent can run shell commands, so it must never be reachable without authentication. This template builds upstream's Ubuntu 26.04 image from the pinned npm releases, runs both processes in one service, and puts a Caddy proxy with HTTP basic auth and a generated password in front of everything except a health check. One volume at `/data` keeps workspaces, sessions, Pi settings and installed tools across restarts and redeploys. You bring an API key for any OpenAI-compatible model provider.

## Common Use Cases

* An always-on coding agent you can reach from any browser or phone, without keeping a laptop awake
* Long agent tasks (refactors, migrations, test runs) that keep going after you close the tab
* A private, password-protected workspace where an agent clones, edits and tests your repositories

## Dependencies for Pi Web Hosting

* An API key for an OpenAI-compatible model provider (OpenAI, OpenRouter, Groq, DeepSeek, a vLLM or Ollama server, and similar)
* A Railway volume at `/data` (included in the template)

### Deployment Dependencies

* [Pi Web](https://github.com/jmfederico/pi-web) 1.202611.5 ([release](https://github.com/jmfederico/pi-web/releases/tag/v1.202611.5), [configuration docs](https://pi-web.dev/config))
* [Pi Coding Agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) 1.6.0
* Template source: [aalfath/pi-web-railway-template](https://github.com/aalfath/pi-web-railway-template)

### Implementation Details

**What you get:** one service, `Pi Web`, built from the template repo: Pi Web 1.202611.5 with Pi Coding Agent 1.6.0 on Ubuntu 26.04 (git, gh, build tools, Python 3, ripgrep, jq and mise for language versions), behind Caddy 2.11.9 on Railway's public domain, with a volume at `/data`.

**Variables:**

* `LLM_API_KEY` (required): your provider's API key, for example from https://platform.openai.com/api-keys or https://openrouter.ai/keys. It stays in Railway's variables; Pi's `models.json` only refers to it.
* `LLM_BASE_URL` (default `https://api.openai.com/v1`) and `LLM_MODEL` (default `gpt-5.4-mini`): any OpenAI-compatible endpoint and model ID, for example `https://openrouter.ai/api/v1`.
* `PI_WEB_PASSWORD`: generated for you; `PI_WEB_USERNAME` is `admin`. The service refuses to start without a password of 12+ characters.

**After deploy:** open the service's public URL, sign in as `admin` with the `PI_WEB_PASSWORD` shown in the service's Variables tab, add a project (for example a new folder under `/data/workspace`, or clone a repository from the terminal), and start a session. You can also add other providers (Anthropic, Google and more) from Pi Web's own settings.

**Memory:** about 210 MB at idle; it runs on a 0.5 GB service, and an `npm install` of a small project fit there in our test. Give it 1 GB or more if the agent builds or runs heavier code. Anything installed outside `/data` is lost on redeploy, so install tools with mise or into the workspace.

**Limits:** Pi Web is a single-user tool, and the agent can run any command inside the container and read its environment, so don't add secrets the agent shouldn't see. There is no Docker socket on Railway, so Pi Web's Docker-based extras (hostexec, in-app updates of the Docker install) are off.

**Updates:** the service builds from the template's GitHub repo, so when the pinned Pi Web version is bumped, Railway shows an "update available" notice. Read the repo's `CHANGELOG.md` first; your data on `/data` is kept.

## Why Deploy Pi Web on Railway?

<!-- Recommended: Keep this section as shown below -->
Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Pi Web on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
<!-- End recommended section -->
