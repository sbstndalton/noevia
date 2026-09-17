# Remote access: Headscale vs NetBird vs staying on Tailscale — research

Roadmap H1 / R10. Written 2026-09-17. **Recommendation: do not migrate yet. Measure the
path first; if self-hosting the control plane is still wanted afterwards, choose Headscale.**

## What was observed

- DaServer runs Tailscale 1.102.4 and offers an exit node. `tailscale netcheck` (2026-09-17):
  UDP works, public IPv4 reachable, `MappingVariesByDestIP: false` (NAT mapping is stable, so
  direct peer connections are feasible), nearest DERP Ashburn at 16 ms.
- The Mac's Tailscale was stopped at the time, so no remote path measurement was possible.
- On 2026-09-14 slow loads were traced to 20–40% packet loss on the home WAN (recorded in the
  deployment notes). That loss affects every overlay equally.

## What each option changes

| | Tailscale (today) | Headscale | NetBird |
|---|---|---|---|
| Control plane | Tailscale SaaS | Self-hosted "implementation of the Tailscale control server", single tailnet | Self-hosted Management + Signal |
| Clients | Official Tailscale apps | **Same official apps**, pointed at a custom control URL (check support per platform before migrating; tvOS in particular) | NetBird clients replace every Tailscale app |
| Data plane | WireGuard, direct when NAT traversal succeeds, else DERP relay | Identical to Tailscale | WireGuard point-to-point, relay (TURN) fallback |
| Relay | Tailscale's DERP fleet | Tailscale DERP or embedded DERP (disabled by default; needs public IPs, TCP 443, UDP 3478 STUN) | Self-hosted or NetBird relay |
| Migration effort | — | Re-login each device to a new control URL; ACLs rewritten | Uninstall/replace on every device; new ACL model |

Neither alternative changes how packets travel when a direct connection exists. They can only
help when traffic is being **relayed**, and only if their relay sits closer or has more
capacity than Tailscale's — a relay hosted at home sits behind the same lossy uplink.

## Measure before deciding (from a remote client, e.g. phone on cellular or laptop away)

1. `tailscale ping daserver` — reports `via DERP(...)` or a direct `ip:port`. Relay means the
   problem is NAT traversal, not the overlay product.
2. `tailscale status` on both ends during a transfer — `relay "iad"` vs `direct`.
3. `iperf3 -c <daserver-tailscale-ip>` for 30 s and `mtr` to DaServer's public IP from the same
   network, repeated at the slow time of day; record loss on the last hop.
4. On the home router: allow UPnP/NAT-PMP, or forward UDP 41641 to DaServer, then repeat 1–3.

## Decision rules

- **Direct path and still slow, with WAN loss in `mtr`:** fix the uplink/ISP; no overlay change.
- **Relayed path:** enable port mapping or forward UDP 41641 first; re-measure.
- **Direct path, clean WAN, still slow:** compare Tailscale's kernel vs userspace WireGuard on
  the Unraid plugin before switching products.
- **Self-hosting wanted for independence or privacy regardless of speed:** Headscale — it keeps
  the official clients already in use (verify custom-server support per platform first) and its single-tailnet
  scope matches one household. Run it on a small VPS rather than behind the home uplink so the
  control plane and optional DERP stay reachable when the home link degrades. NetBird is the
  better fit only if a fully self-hosted client stack is itself the goal.

Sources: headscale.net (overview, embedded DERP reference), docs.netbird.io (how NetBird works),
live `tailscale netcheck`/`status` on DaServer.
