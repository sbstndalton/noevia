# Whole-Diary graph index: bounded offline qualification (#275)

This is a design and synthetic experiment, not a production index or migration.
The Diary sidecar remains authoritative for file content and tenant identity, as
the [service-boundary comparison](../spec-service-boundaries.md) recommends.
The shipped one-hop graph uses the open file plus a bounded backlink scan; that
scan stops after 50 files, 4 MiB, or 30 matches and reports partial results.

## Proposed record and consistency contract

One active Markdown file is a node identified by tenant and canonical path.
Potential directed edges are source path, target path, and kind (Markdown link,
wiki link, or wiki embed), with source revision. Fragment/heading and alias
are link metadata rather than separate nodes. The prototype collapses kinds
and fragments into one edge per source/target to match backlink membership;
production must retain kind if the UI distinguishes embeds. The current
backlink scan counts wiki embeds, while the one-hop drawing omits them.
An unlinked mention is not an edge: it is prose search and cannot be inferred
from link adjacency.

The index must be derived from a committed, tenant-scoped Diary source snapshot.
It should store paths, source revisions and adjacency only, not bodies, snippets,
credentials or prompts. Every request must establish tenant identity at the
Diary boundary before opening that tenant's index. Core still owns the caller's
session and policy gates. A graph query returns a source watermark or generation,
`partial` and hidden count, and a bounded sorted page. If the index is stale,
incomplete, over budget, or unavailable, return an explicit stale/partial state
or use the existing bounded scan. Never label a partial graph complete.

An incremental refresh must occur **after** the authoritative file write and
must replace a source file's old outgoing edges atomically. Deleting or
trashing a source removes its active edges; restoring it re-parses the restored
revision. A rename is delete-old plus insert-new under one source transaction;
relative links in other files can change meaning, so the affected folder or
whole tenant may need re-evaluation. Corrections are ordinary new revisions,
not append-only edges. Concurrent edits and remote sync conflicts must be
resolved by the Diary's source-of-truth rules first. Conflicting or nonmonotonic
revisions stop index publication and trigger a rebuild; last-writer-wins inside
the graph would invent authority. Offline replicas have separate source
watermarks and may show a partial/stale local graph, never a silently merged
global graph. On reconnect, reconcile source files, then rebuild or replay
committed changes in source order.

A production rebuild should scan only one tenant's active source snapshot,
validate path and file-size limits, build a temporary index, and publish it
only after every expected file/revision has been accounted for. Missing reads,
sync conflicts and over-capacity are explicit partial/error states. Keep the
previous generation available until the replacement is complete, but mark it
stale against the new source watermark. Tenant deletion destroys that tenant's
index. Backups need the source corpus and revision history; the derivative
index can be rebuilt and must not be a second source of truth.
The prototype keeps bounded deletion tombstones so an older delayed upsert
cannot resurrect a trashed path. A full rebuild may clear tombstones only when
the Diary supplies a complete authoritative snapshot at a verifiable source
watermark. The prototype's `authoritative` flag is a test assumption, not proof
of that watermark; it can accept an old snapshot if a caller lies. Production
must establish and compare the watermark before publication.

## Synthetic prototype and evidence

Run `node apps/web/qa/diary-graph-prototype.cjs` from the repository root.
The standalone CLI generates Markdown fixtures and reuses the shipped link
parser through a local TypeScript transpile. The exported prototype accepts
caller-provided strings, has no production import, and must not be given real
Diary content. Its in-memory per-tenant maps hold source revisions,
outgoing and incoming path sets without storing content. It implements
revision-checked updates, bounded tombstones, trash/delete, atomic rebuild, a stale-generation
response, missing-node response, a 100-node query ceiling, and configurable
file/edge caps (defaults 5,000/25,000). There is no persistence or API.

One local run on 2026-09-28 produced these illustrative measurements (ms):

| Synthetic files | Edges | Build | Full parser scan for one target | Indexed query | One update | Rebuild | Key-string bytes |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 40 | 78 | 3.13 | 1.12 | 0.29 | 0.08 | 0.59 | 1,770 |
| 400 | 798 | 10.46 | 3.64 | 0.08 | 0.01 | 6.70 | 17,970 |
| 2,000 | 3,998 | 23.50 | 21.33 | 0.25 | 0.01 | 28.56 | 89,970 |

The full-scan comparator parses all generated files in memory; it is **not**
the shipped bounded scan, remote storage I/O, a sidecar benchmark, or a
production latency measurement. Timings vary with machine and warmup and are
not CI pass thresholds. `key-string bytes` counts path strings only, not JS
object overhead or a production storage budget. At 400 and 2,000 files the
hub query is capped and says `partial`; the 40-file result is complete. At all
three scales, an uncapped backlink membership check matched the same parser
applied directly to every synthetic file. A separate small fixture compared
the index against the actual
shipped bounded scanner with Markdown links, wiki links, embeds, code and
fragments. Tests cover two synthetic tenant namespaces, stale/conflicting
revisions, delayed stale resurrection after trash, update, rename-as-delete/add,
capacity failure, atomic rebuild, and partial query counts. No private Diary
content was read. Offline conflict resolution and authoritative snapshot
verification are outside this prototype.

## Decision

**Narrow the next step.** The experiment supports a small tenant-scoped
adjacency index as a plausible way to answer whole-corpus backlinks without
reparsing every file per query. It does not qualify a production rollout:
real storage traversal cost, sync/event ordering, offline reconciliation,
memory overhead, backup/rebuild time and crash recovery remain unmeasured.
Before production work, specify a Diary-owned revision/watermark contract and
run authorized synthetic sidecar/storage tests for failed reads, concurrent
edits, trash/restore and replica conflicts. Keep the shipped partial bounded
scan as the fallback and avoid a new UI until those semantics are proven.
