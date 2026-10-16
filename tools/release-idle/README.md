# Persisted Coding and tuning release check (#1391)

Unexecuted operator source. This package alone replaces the unsafe persisted-state
portion of the prospective old prebuild operator; do not run that old operator.
Source authority is CORE `010735c7d86d30269ab3f4a351b2135faea1c8e7`, tree
`345adfa12da083eb5888ec232dc2d86b9b0383a5`. Seven module/lock Git blob IDs are
embedded in `src/main.rs`; the supplied export is verified byte-for-byte, then
snapshotted privately. The immutable lock pins noevia-rs
`eb14179c2c5d94acce8f9c5f9d1adac7e0af82f5` and WASM SHA256
`040738a438de8241bd2cd1558f2b06beaa32c5c9be01c30f09cd87cb2e978575`.
No source export, WASM or dependency artifact is packaged in this repository.

Future separately authorized Linux invocation:

```text
noevia-release-idle inspect --data-root ABS --evidence-dir NEW_ABS \
  --source-root PINNED_CORE_EXPORT --expected-core 010735c7d86d30269ab3f4a351b2135faea1c8e7 \
  --node ABS_REGULAR_EXECUTABLE --node-sha256 REVIEWED_EXECUTABLE_SHA256
```

Six named arguments are required. Data root is explicit; index.cjs:82 derives
UI_DATA_DIR or server/ui-data at runtime, which the operator does not import.
Evidence must be fresh and outside source/data ancestry. Exit 0 means this
stable **persisted Coding/tuning** scope was idle, 2 means active/refused/unknown,
and 64 means invalid invocation. Public JSON exposes counts and static reasons;
private evidence retains bounded raw journals/tuning, file identities/digests,
fixed source/WASM snapshots and bounded child stdout/stderr, including failures.
Directories are 0700; newly created files are 0600; files never overwrite.
No evidence is deleted by the operator.

## Grounded persisted layout

workspace.cjs:58,78–81 defines users/<36 hex/hyphen ID> (case insensitive).
workspace.cjs:123 creates users/<id> lazily with recursive mkdir; thus stable
absence of users means no persisted account directories, rather than an
unreadable namespace. Root/jobs covers legacy work. Every users entry is
examined; invalid names, non-directories and case collisions refuse. Each
account/jobs directory may be stably absent. All present jobs entries must be
lowercase 36 hex/hyphen IDs with .jsonl, as jobs.cjs:206,209 requires. Unknown
entries refuse; filesystem errors never become empty lists. Complete root,
users and jobs namespaces and every ancestor/file identity are checked again.
Directory ancestors compare dev/inode/mode/owner; namespace manifests compare
full entry identities. A changed inspected file or namespace refuses.

The accepted creation kinds are `code` and `deep_research`. Other kinds,
including source/browser histories, conservatively refuse this release scope.
All journals are parsed before filtering; malformed non-code files cannot hide
Coding work. Every nonempty line, including the final line, must be complete
UTF-8 JSON with unique keys, a matching job ID, contiguous seq, integer-safe at,
object data, known event type and exactly one initial creation. Mixed chain
metadata and malformed hashes refuse before delegation. Actual immutable
createJobs({dir:PRIVATE_SNAPSHOT}).get(id) validates chain hashes and calls
actual derive; no copied hash or business reducer exists. Constructor performs
no IO mutation; get calls only events/derive. No list/create/run/cancel/recover/
prune/append action is invoked. Coarse lifecycle never overrides job status;
unknown authoritative lifecycle additionally refuses. Actual terminal job
statuses stay completed/failed/cancelled/interrupted; queued/running/
waiting_approval count active.

The fixed minimal Node glue imports jobs' reviewed graph: code-plan,
code-review-verdict, task-lifecycle, completeness-report and lazy dav-parse-wasm.
Their remaining imports are built-in fs/path/crypto/net. The actual WASM loader
checks its pinned SHA256, no WASM imports and ABI; verifyAtStartup runs first,
so caught lazy-load failures cannot silently become lifecycle null. No fake
loader or JS hashing substitute is used. Node executes through an inherited
open executable descriptor after byte pin verification; evidence is passed by
directory descriptor, not a live user-data path. Environment is cleared;
NODE_OPTIONS, NODE_PATH, DYLD and LD preload settings cannot be inherited.
No addons are allowed. Builtin WebAssembly and the reviewed Node executable's
OS shared-library ancestry remain explicit trusted runtime dependencies; this
is not a hermetic VM or an RSS limit.

index.cjs:246–247 places native-calibration-<16 lowerhex>.json and
native-autotune-<16 lowerhex>.json at data root; every manager suffix is checked.
Matching temporary or malformed names refuse. Calibration's initial job:null
is valid (llamacpp-calibration.cjs:57–70); absent job in autotune is valid
(llamacpp-full-autotune.cjs:243–249 initializes {}, then history/settings).
These legitimate shapes are distinguished from read/parse errors. Present
job must have running or passed/failed/cancelled/interrupted status; completed,
missing, blank and unknown status refuse. History/settings, when present, must
be objects. No service is constructed, recovered or rewritten.

## Bounds and limitations

Refusal ceilings: 4096 account directories, 16384 root/users entries, 4096
entries per jobs directory, 65536 total journals, 8 MiB per journal, 1 MiB per
tuning file, 65536 events per journal and 256 KiB per event. The 256 MiB retained
budget includes runtime snapshots, journal/tuning bytes and metadata, a fixed
metadata reserve, 1024 bytes reserved per journal binding record, and 16384 bytes reserved per
child command/status/stream/snapshot observation records. Directory limits
are checked while iterating before retaining another name. File size and
remaining aggregate budget are checked before read/copy; cap+1 reads and
before/after fstat refuse growth. Large terminal files refuse as well as active
ones. Single-link regular files only; all traversed paths use descriptor-relative
NOFOLLOW opens, including ancestors. Special files never reach blocking reads.
Missing descriptors, allocations and OS read failures refuse. Numeric limits
are not proofs of process RSS or of admissibility at an exact ceiling.
Source modules have 1 MiB caps, pinned WASM 32 MiB, Node executable 128 MiB.
Each Node child has a five-second observation deadline and 4096 byte stdout/stderr
limits. Every child has a durable fixed command/glue/executable record before spawn,
capped stream files, actual PID and raw exit/signal or an explicit no-child/
unavailable-status record. Setup, restoration, pipe/read, cleanup and retention
faults are distinct. Capture uses nonblocking pipes and a fair finite loop,
without blocking reader threads or joins. NOWAIT observes the owned leader
without reaping it; group kill precedes NOHANG actual-leader reaping, including
normal leader exit with an inherited pipe holder. A further one-second cleanup
observation window closes pipes and refuses if writers remain or the leader
cannot be reaped. Group cleanup is attempted, not proof of escaped-descendant
containment. An ownership-lost wait error refuses without signaling a potentially
reused PID. Kernel syscalls, process spawn and scheduling have no guaranteed
wall-clock limit; incomplete cleanup/status remain explicit holds. Overall scan/derivation has a 60 second elapsed limit; OS filesystem IO
can block independently, so this is not a kernel IO deadline.

Stable persisted state is an observation, not atomic admission exclusion.
Account registry/unseen work, models/benchmarks/downloads/metrics, backup-process
exclusion, startup no-op, consistent DB/WAL/SHM/INI backup, serial overlays and
exclusive-owner Chrome are separate release holds. This tool cannot authorize
or perform deployment. Laya must never restart. No model, inference, chat,
Coding, tuning, account/flag/storage mutation, credential access, SSH, Docker,
network or user-data cleanup actions are part of this tool.

All copied runtime modules/lock/WASM and item/jobs/journal subtrees are
registered against approved copied-byte digests, original held file identities
and complete directory namespace manifests. Binding records are private. All
registered snapshots are rehashed and checked before and after every child,
including failed children, before its JSON is accepted. Replacement, append,
extra entries, modes and link changes refuse. This is a finite observation,
not atomic consumption protection against same-UID/root mutation and restoration,
or a hermetic OS write denial. The owner-readable 0600 read scope remains explicit.

## Validation boundary

Offline compilation and Clippy compile all actual modules and integration test
sources on the existing macOS toolchain; no Linux target is cached. Linux
runtime descriptor inheritance, actual Node/get/WASM agreement, permission
failures, FIFOs/devices, injected concurrent substitution, every resource-cap
boundary and child timeout/overflow remain separate finite synthetic controls
for a later authorized Linux run. Current synthetic test source covers strict
JSON/torn tails/kinds/statuses/chain shapes and caps, filesystem absence versus
symlink, bounded enumeration/hardlinks, mutation detection, and private
non-overwriting evidence. Additional compiled controls use only this Rust test
executable as a synthetic child for normal/nonzero status, overflow, deadline,
pipe-holder and setup failure; dummy synthetic source/journal snapshots cover
append/extra/replacement/mode/link refusal. None were executed. No operator/Node or tests have run yet. Do not treat
compilation as behavioral validation or whole-release readiness.
