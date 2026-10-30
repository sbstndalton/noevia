#!/usr/bin/env bash
# The web image's entrypoint (full-Rust migration M1, docs/adr-0001-rust-and-repo-split.md
# "Amendment 2026-10-10"). noevia-server (noevia-rs bins/noevia-server) faces the network on
# UI_HOST:UI_PORT, Node behind it on UI_PORT+1000 (NOEVIA_LEGACY_UPSTREAM). The front answers the
# routes noevia-rs contracts/http/routes.toml gives to Rust and streams the rest to Node.
#
# sbstndalton/noevia#1071: the front read routes (usage, sampling and reasoning settings, routing
# mode and default, engine statistics, ChatGPT status, connected-storage metadata/list/read and the
# conversation export) and sign-in and the account (rust-auth) are the Rust front's permanently;
# Node no longer has them. So are the project routes (images, project and free chat lists) and the
# project store. The deployment switches NOEVIA_RUST_AUTH and NOEVIA_RUST_PROJECTS are retired: a
# leftover value only warns. So the image runs only with NOEVIA_FRONT=rust and a noevia-server
# whose --features lists rust-auth and every front route feature (FRONT_ROUTE_FEATURES). Anything else stops here, non-zero, before either process starts.
# NOEVIA_FRONT=node is refused for the same reason: Node alone would answer those routes 503.
# If either process exits, the other is stopped and the container exits non-zero, so Docker's
# restart policy brings both back together.
set -uo pipefail

# Only this script may hand out the project store (below);
# never trust a value from the environment. (The retired confirmations, rust-auth's, the projects'
# and the front routes', are scrubbed too, so an inherited value can never reach a Node of either age.)
unset NOEVIA_RUST_AUTH_CONFIRMED NOEVIA_RUST_PROJECTS_CONFIRMED NOEVIA_RUST_PROJECT_CHATS_CONFIRMED NOEVIA_RUST_FREE_CHATS_CONFIRMED NOEVIA_RUST_USAGE_CONFIRMED NOEVIA_RUST_SAMPLING_SETTINGS_CONFIRMED NOEVIA_RUST_REASONING_SETTINGS_CONFIRMED NOEVIA_RUST_ROUTING_MODE_CONFIRMED NOEVIA_RUST_ROUTING_DEFAULT_CONFIRMED NOEVIA_RUST_STATS_CONFIRMED NOEVIA_RUST_EXPORT_CONFIRMED NOEVIA_RUST_STORAGE_READS_CONFIRMED NOEVIA_RUST_STORAGE_BROWSE_CONFIRMED NOEVIA_RUST_CHATGPT_STATUS_CONFIRMED NOEVIA_RUST_PROJECT_WRITES_CONFIRMED NOEVIA_RUST_PROJECT_STORE_CONFIRMED NOEVIA_PROJECT_STORE_PORT NOEVIA_PROJECT_STORE_TOKEN NOEVIA_FRONT_CLIENT_IP NOEVIA_LEGACY_CLAIM_BIN NOEVIA_START_ID
FRONT_ROUTE_FEATURES="rust-chatgpt-status rust-storage-reads rust-storage-browse rust-export rust-free-chats rust-usage rust-stats rust-routing-default rust-sampling-settings rust-reasoning-settings rust-routing-mode rust-projects rust-project-chats rust-project-writes project-store"
# Their old switches only earn a warning now (noevia-server says the same), and neither process
# gets them (each would only warn again).
for retired in NOEVIA_RUST_AUTH NOEVIA_RUST_USAGE NOEVIA_RUST_SAMPLING_SETTINGS NOEVIA_RUST_REASONING_SETTINGS NOEVIA_RUST_ROUTING_MODE \
  NOEVIA_RUST_ROUTING_DEFAULT NOEVIA_RUST_STATS NOEVIA_RUST_EXPORT NOEVIA_RUST_CHATGPT_STATUS NOEVIA_RUST_STORAGE_READS \
  NOEVIA_RUST_STORAGE_BROWSE NOEVIA_RUST_PROJECTS NOEVIA_RUST_PROJECT_WRITES; do
  if [ -n "${!retired+set}" ]; then
    echo "web-supervisor: $retired is retired (sbstndalton/noevia#1071) and ignored; remove it from the environment" >&2
    unset "$retired"
  fi
done
# Rust is the only front (sbstndalton/noevia#1071, #2094): unset or empty means rust, matching the image
# default; node and anything else are refused below.
front="${NOEVIA_FRONT:-rust}"
case "$front" in
  rust) ;;
  node) echo "web-supervisor: NOEVIA_FRONT=node is no longer supported: the Rust front owns sign-in and routes Node no longer has (sbstndalton/noevia#1071); set NOEVIA_FRONT=rust" >&2; exit 2 ;;
  *) echo "web-supervisor: NOEVIA_FRONT must be rust, got '$front'" >&2; exit 2 ;;
esac

bin="${NOEVIA_SERVER_BIN:-/usr/local/bin/noevia-server}"
if [ ! -x "$bin" ]; then
  echo "web-supervisor: NOEVIA_FRONT=rust but this image has no noevia-server (its NOEVIA_RS_REF predates bins/noevia-server); update the image" >&2
  exit 2
fi
# The code-network guard (sbstndalton/noevia#1246): with COWORK_CODE_NET_ADDR set, Node behind
# the front sees every request arrive on loopback, so only the front can refuse code-network
# requests. A front that does not report the guard must not face the network.
# (Captured first: with pipefail, grep -q exiting early could fail the pipeline via SIGPIPE.)
if [ -n "${COWORK_CODE_NET_ADDR:-}" ]; then
  features="$("$bin" --features 2>/dev/null || true)"
else
  features=code-net-guard
fi
if ! grep -qx 'code-net-guard' <<<"$features"; then
  echo "web-supervisor: COWORK_CODE_NET_ADDR is set but this noevia-server has no code-net-guard; update the image" >&2
  exit 2
fi
# The client address (noevia-core server/auth.cjs, #1578): Node believes X-Noevia-Client-Ip from its
# loopback peer only when this front drops client copies of it, which a front reports with
# client-address-header. Node is told so with NOEVIA_FRONT_CLIENT_IP=1; a front that predates the
# strip (a core/rs pin mismatch or an rs rollback) leaves Node on the socket address, never a
# header a client chose. Not an error: the address is the proxy's until the image catches up.
client_features="$("$bin" --features 2>/dev/null || true)"
client_ip_confirmed=""
if grep -qx 'client-address-header' <<<"$client_features"; then
  client_ip_confirmed=1
else
  echo "web-supervisor: this noevia-server has no client-address-header; Node ignores X-Noevia-Client-Ip and sees every client as the front" >&2
fi
# Rust-owned sign-in (noevia-core server/rust-auth.cjs), permanent since #1071: Node always refuses
# to write the account tables and no longer answers sign-in, so the front facing the network must.
# A front whose --features does not list rust-auth never starts.
rust_features="$("$bin" --features 2>/dev/null || true)"
if ! grep -qx 'rust-auth' <<<"$rust_features"; then
  echo "web-supervisor: this noevia-server has no rust-auth; Node no longer answers sign-in (sbstndalton/noevia#1071), so update the image" >&2
  exit 2
fi
# The permanent front read routes (#1071): every feature, or nothing starts.
missing=""
for feature in $FRONT_ROUTE_FEATURES; do
  grep -qx -- "$feature" <<<"$rust_features" || missing="$missing $feature"
done
if [ -n "$missing" ]; then
  echo "web-supervisor: this noevia-server lacks the front route feature(s):$missing; Node no longer answers those routes (sbstndalton/noevia#1071), so update the image" >&2
  exit 2
fi
# Compare the baked Core entrypoint with the actual selected binary, independently of
# environment switches. Old/old images remain usable for rollback; mixed owners do not.
feature_core_owner=""
feature_front_owner=""
grep -qF '.createReadOnlyFeatures(' "$PWD/server/index.cjs" 2>/dev/null && feature_core_owner=rust
grep -qx 'rust-feature-owner' <<<"$rust_features" && feature_front_owner=rust
if [ "$feature_core_owner" != "$feature_front_owner" ]; then
  echo "web-supervisor: feature ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# The five proxy-only Diary routes (sbstndalton/noevia#2185): a Core that refuses them
# (server/rust-diary.cjs) needs a front that answers them (rust-diary), and a rust-diary front
# needs that Core. Old/old images remain usable for rollback; mixed owners do not.
diary_core_owner=""
diary_front_owner=""
grep -qF "require('./rust-diary.cjs')" "$PWD/server/index.cjs" 2>/dev/null && diary_core_owner=rust
grep -qx 'rust-diary' <<<"$rust_features" && diary_front_owner=rust
if [ "$diary_core_owner" != "$diary_front_owner" ]; then
  echo "web-supervisor: Diary route ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# The two configuration-only model reads (sbstndalton/noevia#2187, GET /api/models/capabilities and
# GET /api/models/hardware): a Core that refuses them (server/rust-models.cjs) needs a front that
# answers them (rust-model-reads), and a rust-model-reads front needs that Core. Old/old images
# remain usable for rollback; mixed owners do not.
models_core_owner=""
models_front_owner=""
grep -qF "require('./rust-models.cjs')" "$PWD/server/index.cjs" 2>/dev/null && models_core_owner=rust
grep -qx 'rust-model-reads' <<<"$rust_features" && models_front_owner=rust
if [ "$models_core_owner" != "$models_front_owner" ]; then
  echo "web-supervisor: model read route ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# A project source's stored reads (sbstndalton/noevia#2191: GET .../sources/text, .../documents/original
# and .../uploads/original): a Core that refuses them (server/rust-project-reads.cjs) needs a front that
# answers them (rust-project-reads), and a rust-project-reads front needs that Core. Old/old images
# remain usable for rollback; mixed owners do not.
project_reads_core_owner=""
project_reads_front_owner=""
grep -qF "require('./rust-project-reads.cjs')" "$PWD/server/index.cjs" 2>/dev/null && project_reads_core_owner=rust
grep -qx 'rust-project-reads' <<<"$rust_features" && project_reads_front_owner=rust
if [ "$project_reads_core_owner" != "$project_reads_front_owner" ]; then
  echo "web-supervisor: project source read ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# A project's create and delete (sbstndalton/noevia#2191 round 2: POST /api/projects, DELETE
# /api/projects/{projectId}): a Core that refuses them (server/rust-project-lifecycle.cjs) needs a front
# that answers them (rust-project-lifecycle), and a rust-project-lifecycle front needs that Core (it also
# publishes the toolbox catalogue the create reads and drains the index outbox). Old/old images remain
# usable for rollback; mixed owners do not.
project_lifecycle_core_owner=""
project_lifecycle_front_owner=""
grep -qF "require('./rust-project-lifecycle.cjs')" "$PWD/server/index.cjs" 2>/dev/null && project_lifecycle_core_owner=rust
grep -qx 'rust-project-lifecycle' <<<"$rust_features" && project_lifecycle_front_owner=rust
if [ "$project_lifecycle_core_owner" != "$project_lifecycle_front_owner" ]; then
  echo "web-supervisor: project create/delete ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# A project's storage writes (sbstndalton/noevia#2191 round 3): a Core whose outbox executor claims only
# its own job kinds (server/rust-project-storage.cjs, required by index.cjs) needs a front that runs the
# storage sweep jobs and #687's create-time storage step itself (rust-project-storage), and such a front
# needs that Core (an older one would run the same sweeps). Old/old images remain usable for rollback.
project_storage_core_owner=""
project_storage_front_owner=""
grep -qF "require('./rust-project-storage.cjs')" "$PWD/server/index.cjs" 2>/dev/null && project_storage_core_owner=rust
grep -qx 'rust-project-storage' <<<"$rust_features" && project_storage_front_owner=rust
if [ "$project_storage_core_owner" != "$project_storage_front_owner" ]; then
  echo "web-supervisor: project storage write ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# A project source file's delete (sbstndalton/noevia#2191 round 3: DELETE /api/projects/{id}/files): a
# Core that refuses it (server/rust-project-files.cjs) and runs the `unindex` jobs needs a front that
# answers it (rust-project-files), and such a front needs that Core. Old/old remains usable for rollback.
project_files_core_owner=""
project_files_front_owner=""
grep -qF "require('./rust-project-files.cjs')" "$PWD/server/index.cjs" 2>/dev/null && project_files_core_owner=rust
grep -qx 'rust-project-files' <<<"$rust_features" && project_files_front_owner=rust
if [ "$project_files_core_owner" != "$project_files_front_owner" ]; then
  echo "web-supervisor: project file delete ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# A stored document's page reader (sbstndalton/noevia#2191 round 4: GET /api/projects/{id}/documents/pages):
# a Core that refuses it (server/rust-project-document-pages.cjs) needs a front that answers it
# (rust-project-document-pages), and such a front needs that Core. Old/old remains usable for rollback.
document_pages_core_owner=""
document_pages_front_owner=""
grep -qF "require('./rust-project-document-pages.cjs')" "$PWD/server/index.cjs" 2>/dev/null && document_pages_core_owner=rust
grep -qx 'rust-project-document-pages' <<<"$rust_features" && document_pages_front_owner=rust
if [ "$document_pages_core_owner" != "$document_pages_front_owner" ]; then
  echo "web-supervisor: project document page reader ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# The conversation import (sbstndalton/noevia#2191 round 4: POST /api/import/conversations): a Core that
# refuses it (server/rust-conversation-import.cjs) needs a front that answers it (rust-conversation-import),
# and such a front needs that Core. Old/old remains usable for rollback.
conversation_import_core_owner=""
conversation_import_front_owner=""
grep -qF "require('./rust-conversation-import.cjs')" "$PWD/server/index.cjs" 2>/dev/null && conversation_import_core_owner=rust
grep -qx 'rust-conversation-import' <<<"$rust_features" && conversation_import_front_owner=rust
if [ "$conversation_import_core_owner" != "$conversation_import_front_owner" ]; then
  echo "web-supervisor: conversation import ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# The project document upload (sbstndalton/noevia#2191 round 5: POST /api/projects/{id}/documents, on the
# front's Docling extraction pipeline): a Core that refuses it (server/rust-project-documents.cjs) needs a
# front that answers it (rust-project-documents), and such a front needs that Core. Old/old stays usable.
project_documents_core_owner=""
project_documents_front_owner=""
grep -qF "require('./rust-project-documents.cjs')" "$PWD/server/index.cjs" 2>/dev/null && project_documents_core_owner=rust
grep -qx 'rust-project-documents' <<<"$rust_features" && project_documents_front_owner=rust
if [ "$project_documents_core_owner" != "$project_documents_front_owner" ]; then
  echo "web-supervisor: project document upload ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# The public pages and the device approval page (sbstndalton/noevia#2190, server/rust-public-pages.cjs
# beside the front's rust-public-pages), and the plugin directory (server/rust-plugin-directory.cjs
# beside rust-plugin-directory), and the decision settings (server/rust-decision-settings.cjs beside
# rust-decision-settings; Rust is the decision:configuration row's single writer), and the storage
# integrations (server/rust-storage-integrations.cjs beside rust-storage-integrations; Rust owns the
# Nextcloud sign-in's flows file), and the vault-mirror preferences (server/rust-vault-mirror-preferences.cjs
# beside rust-vault-mirror-preferences; Rust writes the setting and the nudges Node polls), and the
# storage connection save (server/rust-storage-connection.cjs beside rust-storage-connection, round 4;
# Rust is the storage_connections row's only writer and saves Node's legacy WebDAV setup through the
# internal store), the provider probe (server/rust-provider-test.cjs beside rust-provider-test,
# round 4), and Sign in with ChatGPT's token broker (server/rust-chatgpt-oauth.cjs beside
# rust-chatgpt-oauth, round 5; Rust owns the device sign-in, the tokens and their refresh, and Node's
# chat asks it for access tokens through the internal store), and the provider model lists
# (server/rust-provider-models.cjs beside rust-provider-models, round 5), and the provider registry
# (server/rust-providers.cjs beside rust-providers, round 6; Rust is the only writer of providers.json
# and shared-providers.json and Node re-reads them), and its key re-seal (server/rust-providers-reseal.cjs
# beside rust-providers-reseal, round 6 review; a Core that rotates secrets through the front's internal
# store needs a front that answers it, and a front that has it needs that Core, so Node never rewrites a
# provider file the front owns), Google Drive's token authority
# (server/rust-google-drive.cjs beside rust-google-drive, round 7; Rust owns the sign-ins, the sealed refresh tokens
# and tool_policies, and Node's chat tools ask it for access tokens through the internal store), the off-site
# backup (server/rust-offsite-backup.cjs beside rust-offsite-backup, round 7) and the MCP server credentials
# (server/rust-mcp-credentials.cjs beside rust-mcp-credentials, sbstndalton/noevia#2202; Rust is the broker of every
# account's OAuth sign-ins and own server keys, the only writer of their three tables, and Node's chat asks it for
# one call's access token or key headers), and since round 2 the admin MCP directory (server/rust-mcp-directory.cjs
# beside rust-mcp-directory; Rust lists a candidate server's tools itself and is the only writer of
# directory_mcp_servers, Node re-reads it), the permitted-tools view (server/rust-toolboxes-permitted.cjs beside
# rust-toolboxes-permitted) and the connectors list (server/rust-connectors.cjs beside rust-connectors), the last two
# computed by the front from the discovery snapshot Node publishes: each group moves as one owner. Old/old images
# remain usable for rollback; mixed owners do not.
while read -r pair_marker pair_capability pair_label; do
  pair_core_owner=""
  pair_front_owner=""
  grep -qF "require('./$pair_marker')" "$PWD/server/index.cjs" 2>/dev/null && pair_core_owner=rust
  grep -qx "$pair_capability" <<<"$rust_features" && pair_front_owner=rust
  if [ "$pair_core_owner" != "$pair_front_owner" ]; then
    echo "web-supervisor: $pair_label route ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
    exit 2
  fi
done <<'PAIRS'
rust-public-pages.cjs rust-public-pages public page
rust-plugin-directory.cjs rust-plugin-directory plugin directory
rust-decision-settings.cjs rust-decision-settings decision settings
rust-storage-integrations.cjs rust-storage-integrations storage integration
rust-vault-mirror-preferences.cjs rust-vault-mirror-preferences vault mirror preference
rust-storage-connection.cjs rust-storage-connection storage connection
rust-provider-test.cjs rust-provider-test provider test
rust-chatgpt-oauth.cjs rust-chatgpt-oauth ChatGPT sign-in
rust-provider-models.cjs rust-provider-models provider model list
rust-providers.cjs rust-providers provider registry
rust-providers-reseal.cjs rust-providers-reseal provider key reseal
rust-google-drive.cjs rust-google-drive Google Drive
rust-offsite-backup.cjs rust-offsite-backup off-site backup
rust-mcp-credentials.cjs rust-mcp-credentials MCP credential
rust-mcp-directory.cjs rust-mcp-directory MCP directory
rust-toolboxes-permitted.cjs rust-toolboxes-permitted permitted tools
rust-connectors.cjs rust-connectors connectors
PAIRS
# The two read-only model sizing reads (sbstndalton/noevia#2189, GET /api/models/estimate and GET
# /api/models/preset/suggest): a Core that refuses them (server/rust-model-sizing.cjs) needs a front
# that answers them (rust-model-sizing), and a rust-model-sizing front needs that Core. Old/old images
# remain usable for rollback; mixed owners do not.
sizing_core_owner=""
sizing_front_owner=""
grep -qF "require('./rust-model-sizing.cjs')" "$PWD/server/index.cjs" 2>/dev/null && sizing_core_owner=rust
grep -qx 'rust-model-sizing' <<<"$rust_features" && sizing_front_owner=rust
if [ "$sizing_core_owner" != "$sizing_front_owner" ]; then
  echo "web-supervisor: model sizing route ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi

# The three web-address GETs are a paired owner change. The front's compiled capability
# and core's exported marker must agree before either process starts; source pins alone cannot
# protect a manually mixed installed pair. Neither result comes from an inherited environment.
web_address_front_owner=""
grep -qx 'rust-web-address-read' <<<"$rust_features" && web_address_front_owner=rust
web_address_core_owner="$(node -e "try { const m = require('./server/rust-web-address.cjs'); if (m.WEB_ADDRESS_READ_OWNER === 'noevia-web-address-read-rust/1') process.stdout.write('rust'); } catch {}" 2>/dev/null || true)"
if [ "$web_address_front_owner" != "$web_address_core_owner" ]; then
  echo "web-supervisor: web-address GET ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# Both POST actions move together. A binary/core mismatch is refused before either starts.
web_write_front_owner=""
grep -qx 'rust-web-address-write' <<<"$rust_features" && web_write_front_owner=rust
web_write_core_owner="$(node -e "try { const m = require('./server/rust-web-address.cjs'); if (m.WEB_ADDRESS_WRITE_OWNER === 'noevia-web-address-write-rust/1') process.stdout.write('rust'); } catch {}" 2>/dev/null || true)"
if [ "$web_write_front_owner" != "$web_write_core_owner" ]; then
  echo "web-supervisor: web-address POST ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# Source job journals are a paired internal-store capability: this Node client has no local
# source journal fallback. Probe the installed client export and the actual front binary before
# either process starts. The release assembler also checks their canonical source declarations.
source_client_file="$PWD/server/project-store-client.cjs"
source_client_marker="$(node -e 'const c=require(process.argv[1]); if(c.SOURCE_JOBS_CLIENT_MARKER) process.stdout.write(c.SOURCE_JOBS_CLIENT_MARKER)' "$source_client_file" 2>/dev/null || true)"
if { grep -qE 'SOURCE_JOBS_CLIENT_MARKER|sourceJobsFor\(' "$source_client_file" 2>/dev/null \
     || grep -qF 'workspace.sourceJobs' "$PWD/server/source-jobs.cjs" 2>/dev/null; } \
   && [ "$source_client_marker" != 'noevia-source-jobs-client/1' ]; then
  echo "web-supervisor: core declares a source job store client but does not export its canonical capability" >&2
  exit 2
fi
if [ -n "$source_client_marker" ] && [ "$source_client_marker" != 'noevia-source-jobs-client/1' ]; then
  echo "web-supervisor: unknown source job client capability" >&2
  exit 2
fi
source_store_reported=""
if grep -qx 'noevia-source-jobs-store/1' <<<"$rust_features"; then source_store_reported=1; fi
if [ -n "$source_client_marker" ] && [ -z "$source_store_reported" ]; then
  echo "web-supervisor: core source job client requires noevia-source-jobs-store/1 from this noevia-server" >&2
  exit 2
fi
if [ -z "$source_client_marker" ] && [ -n "$source_store_reported" ]; then
  echo "web-supervisor: noevia-server source job store requires a paired core source job client" >&2
  exit 2
fi
# The source jobs (sbstndalton/noevia#2191 round 6): the front becomes the one owning process of the
# source-job store and Node keeps no source journal client. A Core that refuses the background starts
# and the poll (server/rust-source-jobs.cjs) needs a front that answers them (rust-source-jobs), and
# such a front needs that Core. The older pair (Node's client, the front's internal store) is checked
# above; old/old stays usable.
source_jobs_core_owner=""
source_jobs_front_owner=""
grep -qF "require('./rust-source-jobs.cjs')" "$PWD/server/index.cjs" 2>/dev/null && source_jobs_core_owner=rust
grep -qx 'rust-source-jobs' <<<"$rust_features" && source_jobs_front_owner=rust
if [ "$source_jobs_core_owner" != "$source_jobs_front_owner" ]; then
  echo "web-supervisor: source job ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# The project source operations (sbstndalton/noevia#2191 round 8): the upload, the folder sync and the folder
# import's plan run in the front, with no worker call to Node. A Core that refuses them
# (server/rust-project-source-work.cjs) and reads the front's storage latch and file-operation list needs a
# front that runs them (rust-project-source-work), and such a front needs that Core. Old/old stays usable.
source_work_core_owner=""
source_work_front_owner=""
grep -qF "require('./rust-project-source-work.cjs')" "$PWD/server/index.cjs" 2>/dev/null && source_work_core_owner=rust
grep -qx 'rust-project-source-work' <<<"$rust_features" && source_work_front_owner=rust
if [ "$source_work_core_owner" != "$source_work_front_owner" ]; then
  echo "web-supervisor: project source operations ownership mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# In that generation Core keeps no worker path: a Core that refuses the source operations but still ships the
# worker call (its registry, folder import, PDF reduction or the worker header) would run them a second time.
if [ "$source_work_core_owner" = rust ]; then
  for worker_file in source-work.cjs folder-import.cjs pdf-reduce.cjs; do
    if [ -e "$PWD/server/$worker_file" ]; then
      echo "web-supervisor: project source operations ownership mismatch between noevia-server and noevia-core (Core still carries server/$worker_file); update the paired image" >&2
      exit 2
    fi
  done
  if grep -qiF 'x-noevia-source-work' "$PWD/server/routes/projects.cjs" "$PWD/server/index.cjs" 2>/dev/null; then
    echo "web-supervisor: project source operations ownership mismatch between noevia-server and noevia-core (Core still answers the worker call); update the paired image" >&2
    exit 2
  fi
fi
# The large-document lock (sbstndalton/noevia#2191 round 7, #697): a core whose large-document-lock.cjs
# also takes the host-wide lock file (large-document-file-lock.cjs) needs a front that takes it too
# (rust-large-document-host-lock), and the reverse; otherwise the two could each hold a document over
# 25 MiB at once. Old/old stays usable.
large_lock_core_owner=""
large_lock_front_owner=""
grep -qF "require('./large-document-file-lock.cjs')" "$PWD/server/large-document-lock.cjs" 2>/dev/null && large_lock_core_owner=host
grep -qx 'rust-large-document-host-lock' <<<"$rust_features" && large_lock_front_owner=host
if [ "$large_lock_core_owner" != "$large_lock_front_owner" ]; then
  echo "web-supervisor: large-document lock mismatch between noevia-server and noevia-core; update the paired image" >&2
  exit 2
fi
# The deep-research executor also requires a paired Rust journal store. Probe the real
# client export and this binary's compiled feature before starting either process.
research_client_file="$PWD/server/project-store-client.cjs"
research_client_marker="$(node -e 'const c=require(process.argv[1]); if(c.RESEARCH_JOBS_CLIENT_MARKER) process.stdout.write(c.RESEARCH_JOBS_CLIENT_MARKER)' "$research_client_file" 2>/dev/null || true)"
if { grep -qE 'RESEARCH_JOBS_CLIENT_MARKER|researchJobsFor\(' "$research_client_file" 2>/dev/null      || grep -qF 'workspace.researchJobs' "$PWD/server/research-jobs.cjs" 2>/dev/null; }    && [ "$research_client_marker" != 'noevia-research-jobs-client/1' ]; then
  echo "web-supervisor: core declares a research job store client but does not export its canonical capability" >&2
  exit 2
fi
if [ -n "$research_client_marker" ] && [ "$research_client_marker" != 'noevia-research-jobs-client/1' ]; then
  echo "web-supervisor: unknown research job client capability" >&2
  exit 2
fi
research_store_reported=""
if grep -qx 'noevia-research-jobs-store/1' <<<"$rust_features"; then research_store_reported=1; fi
if [ -n "$research_client_marker" ] && [ -z "$research_store_reported" ]; then
  echo "web-supervisor: core research job client requires noevia-research-jobs-store/1 from this noevia-server" >&2
  exit 2
fi
if [ -z "$research_client_marker" ] && [ -n "$research_store_reported" ]; then
  echo "web-supervisor: noevia-server research job store requires a paired core research job client" >&2
  exit 2
fi
# #2027: Node's legacy workspace prologue delegates only to the actual selected front
# when that binary advertises the filesystem-only helper. Never inherit an arbitrary path.
legacy_claim_bin=""
if grep -qx 'legacy-root-claim' <<<"$rust_features"; then
  case "$bin" in
    /*) legacy_claim_bin="$bin" ;;
    *) echo "web-supervisor: legacy-root-claim requires an absolute NOEVIA_SERVER_BIN" >&2; exit 2 ;;
  esac
fi
port="${UI_PORT:-8021}"
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 64535 ]; then
  echo "web-supervisor: UI_PORT '$port' leaves no room for the legacy port UI_PORT+1000" >&2
  exit 2
fi
legacy=$((port + 1000))

# The project store (sbstndalton/noevia#1264): permanent. Node writes projects.json and
# free-chats.json only through the front's loopback store and refuses to start without it, so it is
# always set up: at UI_PORT+2000, with a secret made here for this start and handed to both
# processes (never taken from the environment). The front lists project-store (FRONT_ROUTE_FEATURES).
store_port=$((port + 2000))
if [ "$store_port" -gt 65535 ]; then
  echo "web-supervisor: UI_PORT '$port' leaves no room for the project store port UI_PORT+2000" >&2
  exit 2
fi
store_token="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
if [ "${#store_token}" -ne 64 ]; then
  echo "web-supervisor: could not make the project store secret" >&2
  exit 2
fi

# The start id (sbstndalton/noevia#1071): one random id per container start, made here and handed
# to both processes (never taken from the environment). Node writes it into a running reply's
# partial file (core chat-partial.cjs `running: { start }`), so the front can tell a reply still
# running in this start from one a crash or restart cut off; a front that reads it (--features
# start-id) refuses to start beside Node without it.
start_id="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"
if ! [[ "$start_id" =~ ^[0-9a-f]{32}$ ]]; then
  echo "web-supervisor: could not make the start id" >&2
  exit 2
fi

# Node binds UI_HOST for the UI listener AND the Diary file-sharing (DAV) listener. With DAV off
# the legacy port is loopback-only; with DAV on, Node keeps UI_HOST so DAV stays reachable, and
# the legacy port is then reachable from the container's networks too (never published by
# Compose; the same exposure Node's UI port has today) until core splits the two bind hosts.
node_host="127.0.0.1"
if [ -n "${COWORK_DAV_PORT:-}" ] && [ "${COWORK_DAV_PORT}" != 0 ]; then
  node_host="${UI_HOST:-0.0.0.0}"
  echo "web-supervisor: COWORK_DAV_PORT is set; Node's legacy port $legacy listens on $node_host, not loopback only" >&2
fi

node_pid="" front_pid="" signalled=0
stop() {
  local p
  for p in "$node_pid" "$front_pid"; do
    [ -n "$p" ] && kill -TERM "$p" 2>/dev/null
  done
  return 0
}
trap 'signalled=1; stop' TERM INT

UI_HOST="$node_host" UI_PORT="$legacy" \
  NOEVIA_FRONT_CLIENT_IP="$client_ip_confirmed" \
  NOEVIA_LEGACY_CLAIM_BIN="$legacy_claim_bin" \
  NOEVIA_PROJECT_STORE_PORT="$store_port" NOEVIA_PROJECT_STORE_TOKEN="$store_token" \
  NOEVIA_START_ID="$start_id" \
  node server/index.cjs &
node_pid=$!
NOEVIA_PROJECT_STORE_PORT="$store_port" NOEVIA_PROJECT_STORE_TOKEN="$store_token" \
  NOEVIA_START_ID="$start_id" NOEVIA_LEGACY_UPSTREAM="http://127.0.0.1:$legacy" "$bin" &
front_pid=$!

# Whichever exits first (or a signal) ends the wait.
wait -n "$node_pid" "$front_pid"
code=$?
if [ "$signalled" = 0 ]; then
  if kill -0 "$node_pid" 2>/dev/null; then which=noevia-server; else which=node; fi
  echo "web-supervisor: $which exited ($code); stopping the other" >&2
fi
stop
wait "$node_pid" 2>/dev/null
wait "$front_pid" 2>/dev/null
# docker stop: a clean exit. Anything else: non-zero, even when the process that left said 0.
[ "$signalled" = 1 ] && exit 0
[ "$code" = 0 ] && code=1
exit "$code"
