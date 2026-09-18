# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

The server's admin (the owner, technical, runs it on a home Unraid box) plus a few people they
invite to the same server. Each has their own account and private diary. Most use is in a desktop
browser; phones come second but everything has to work on them. (Confirmed 2026-09-18.)

## Product Purpose

noevia is a self-hosted AI workspace over a local model engine (llama.cpp): chat, projects with
sources, a private diary, MCP connectors with tool calling, model management and backups. Nothing
leaves the server unless the user connects something that sends it. Success means everyday AI work
without a cloud subscription, and the owner always knows what the model can touch.

## Positioning

A local, multi-user workspace that shows its machine: inference state, model fit against this
server's memory, and a human approval gate on every write. Hosted assistants can't truthfully
claim "runs on your box, and you can see it running".

## Operating Context

The admin sets up, deploys and monitors from the browser (no terminal handoffs). Invited users chat,
keep a diary and use projects. Connectors include Google Drive (which also carries offsite
backups), Nextcloud and custom MCP servers added by URL. Skills and plugins come from a marketplace
of Claude-compatible repositories, any GitHub repo, your own imports and a curated noevia list.

## Capabilities and Constraints

- Tenant isolation between accounts; every write asks for approval (three approval actions).
- Voice is planned, not built: show it as unavailable, never as a working control.
- Out of scope for this web app: billing/plans, browser and computer use, desktop-app extensions,
  Reveal in Finder.
- Internal `cowork` identifiers (env vars, cookies, storage keys) are compatibility contracts.
- Stack: React 19 + Vite + plain CSS (no Tailwind), Node server.

## Brand Commitments

Name: **noevia**, lowercase. The visual direction is pinned by the user's brief
(docs/ui-overhaul-master-prompt.md): Apple HIG discipline, Material 3 color roles with Ramps
Studio character, Aero/UniFi structural panes, Liquid Glass only on foreground controls. The
pre-2026-09-18 look is not a reference.

## Evidence on Hand

Real usage counts come from the server (tokens, replies, activity days). There are no customers,
testimonials, install counts or benchmarks to show; never fabricate them. Marketplace install
counts only when a source provides them.

## Product Principles

1. Show real state: online/offline, loaded model and approval status are always truthful.
2. Setup happens in the app, one pane at a time. Never tell the user to paste a command.
3. Nothing fake: unavailable features look unavailable.
4. Private by default: the diary and each account's data stay theirs.

## Accessibility & Inclusion

WCAG AA as a floor (primary text 7:1 on its surfaces), visible focus on every surface including
glass, 44px touch targets on phones, and reduced motion and transparency preferences honored.
