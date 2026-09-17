# AIO-style master container — research and Docker socket threat model

Roadmap H2 / R11. Written 2026-09-17. **Recommendation: do not build a master container now.
Harden the one component that already holds the Docker socket (done in this change for the
repository; the live deployment needs the operator steps below), keep Compose Manager as the
lifecycle owner, and revisit only if fresh-install onboarding needs one-click lifecycle.**

## Idea

Nextcloud AIO ships a "mastercontainer" that holds the Docker socket and creates, updates and
backs up the rest of the stack from a web UI. The equivalent here would repurpose the model
manager (which already controls llama containers through the socket) to own every noevia
container.

## Threat model of the Docker socket

- `/var/run/docker.sock` is root-equivalent on the host: any caller can start a privileged
  container with `/` bind-mounted. Read-only mounting the socket file does not restrict the API.
- Today `cowork-model-loader-1` mounts the socket read-write and uses: `containers.list/get`,
  container `attrs`, `logs`, `restart`, one `exec_run`, and `containers.run` (benchmark sweeps
  with `network_mode: none`, removed afterwards).
- **Finding (2026-09-17, live, read-only check):** model-loader served its API without
  authentication on the default Compose network, shared with `cowork-diary-1` and
  `cowork-llama-1`. From inside the Diary container, `GET http://model-loader:8090/api/v1/health`
  succeeded. A compromise of the Diary sidecar (which handles model output and imported
  files) or of the engine could therefore reach socket-backed actions. The web proxy's
  admin-only check does not help, because those containers bypass the web service.

## Fix in this change

1. `MODEL_LOADER_TOKEN`: when set, every model-manager route except `/api/v1/health` requires
   `X-Model-Loader-Token` (constant-time compare); the web proxy sends it. Compose now requires
   it for model-loader and passes it to web. Unit tests cover all route kinds.
2. Network isolation: model-loader joins only a new `models` network with `web` and `llama`;
   `diary` stays on `default` and can no longer resolve it. Both compose variants render as
   intended (`docker compose config` on DaServer, temp directory).

The engine still shares a network with model-loader (model-loader needs `llama:8080`), so the
token is the boundary for that path.

## Live deployment steps (operator, not applied automatically)

1. `openssl rand -hex 32` → add `MODEL_LOADER_TOKEN` to the Compose Manager `.env`.
2. Apply the `unraid-llamacpp.override.yml` changes (token env on model-loader and web,
   `networks: [models]` on model-loader and web, `[default, models]` on llama, top-level
   `networks: models: {}`) to the live Compose Manager file.
3. Rebuild/redeploy with the release flow in `deployment.md`, then verify: Diary container
   cannot resolve `model-loader`; Settings → Models & routing still works.

## Master container options if ever wanted

| Option | Socket exposure | Notes |
|---|---|---|
| Keep Compose Manager (recommended) | Only model-loader, now token-gated and isolated | Unraid-native; no new privileged service |
| Socket proxy (e.g. an allowlisting proxy in front of the socket) | Proxy holds the socket; model-loader gets only listed endpoints | Worth adding before any new socket consumer; `containers.run` cannot be meaningfully restricted by endpoint alone |
| Master container (AIO-style) | One service with full socket, public-facing UI | Largest blast radius; needs its own auth, update signing and backup design |

Revisit when: a fresh-install flow needs lifecycle actions from the browser, or a second
socket consumer is proposed.
