# Lessons

## Xray DNS And Local Filtering

- Root-cause pattern: using `localhost` as Xray's server-side DNS couples proxy routing to whatever local resolver is installed. If that resolver is AdGuardHome or another filtering DNS, blocked domains can resolve to `0.0.0.0`, `127.0.0.1`, or `::1`; Xray then attempts to route or dial those addresses and user-facing requests appear to hang.
- Preventive rule: when the operator expects proxy traffic to keep AdGuardHome filtering, keep Xray DNS on `localhost` and add an early routing rule that sends sinkhole addresses (`0.0.0.0`, loopback, `::`, `::1`) to `blackhole-out` so blocked requests fail fast instead of being dialed.
- Root-cause pattern: some filtering DNS setups return a valid A record and a sinkhole AAAA record (`::`) for the same normal domain. With Xray DNS `queryStrategy=UseIP`, the sinkhole AAAA can win routing and send an otherwise reachable domain to `blackhole-out`.
- Preventive rule: if the operator requires `UseIP`, keep Xray on `UseIP` and fix the filtering resolver instead: configure AdGuardHome blocked responses as `nxdomain` or `refused` so blocked domains produce DNS errors rather than fake sinkhole IPs.
- Root-cause pattern: AdGuardHome runtime status used to print "DNS server configured successfully" even if writing `/etc/resolv.conf` failed with `Operation not permitted`, commonly because the file was immutable, read-only, or managed by another DNS service.
- Preventive rule: DNS switching helpers must return failure on write errors, try `chattr -i` before direct `/etc/resolv.conf` writes, skip rewrites when the intended local nameserver is already present, and only print success after verifying the target nameserver is actually configured.

## WARP Public Source Rules

- Root-cause pattern: WARP non-global mode relies on public-source `ip rule` entries in `/etc/wireguard/warp.conf` so server-originated/public-IP traffic returns through the VPS main route instead of the WARP table. Treating the generated public IPv4 value as a disposable probe value can break routing.
- Preventive rule: do not edit `LAN4`/`USERIP4`-style WARP source rules during unrelated Xray or DNS debugging unless the current public IPv4, domain A record, file value, and live `ip rule` disagree and the intended replacement is explicit.

## Protocol Latency Isolation

- Root-cause pattern: VLESS Reality TCP long-tail latency can be misattributed to REALITY `mldsa65Verify` or VLESS ML-KEM parameters. The active client may not use ML-KEM at all, and removing `mldsa65Verify` does not prove improvement unless the same endpoint is tested side by side.
- Preventive rule: isolate protocol transport before blaming cryptographic options. Run matched temporary clients with and without `mldsa65Verify`, then compare against Hysteria2/QUIC on the same server and URLs. If Hysteria2 removes the long tail while Reality TCP still shows it, prefer Hysteria2 for daily use and keep the post-quantum settings intact.
- Root-cause pattern: Reality `pqv` is derived from `mldsa65Seed`, not from the target domain, but target suitability still depends on the current target certificate chain. Reusing an existing seed without rechecking the new target can leave stale `pqv` enabled after switching to an unsuitable target.
- Preventive rule: always rerun the target PQ suitability check when Reality target changes or when rendering Reality configs. Keep the existing seed only if the current target still allows ML-DSA-65; otherwise clear seed/verify before rendering links.
- Root-cause pattern: `xray tls ping` can report both no-SNI and SNI handshakes. Reading the first certificate length, PQ status, or SAN list can validate the wrong certificate when the target returns different certificates without SNI and with SNI.
- Preventive rule: Reality target validation must prefer the final/SNI handshake values from `xray tls ping` for certificate length, PQ status, and allowed domains.
- Root-cause pattern: a Reality target can pass ordinary TLS ping, SAN matching, and certificate-length checks while still failing real Reality verification. For example, `packages.microsoft.com` passes Xray `tls ping` but triggers a TLS 1.3 HelloRetryRequest/P-256 certificate-flight path that is unsuitable for Reality substitution.
- Preventive rule: split Reality target checks into basic Reality and PQ, and use official Xray output first. Basic Reality uses `xray tls ping` for TCP/TLS 1.3/SAN/certificate-chain facts, while PQ uses only the official `TLS Post-Quantum key exchange` field for Post-Quantum and `pqv` suitability. Do not put temporary generated Reality server/client configs, embedded custom clients, or Python probes in `lib/tls.sh`; use `openssl s_client -trace -tls1_3` only as a lightweight certificate-flight gap check, and use a dedicated analyzer or upstream Xray-core command when exact `uConn.Verified` output is required.

## Hysteria2 Port Reconfiguration

- Root-cause pattern: Hysteria2 reconfiguration can misclassify UDP/443 as externally occupied when `lsof` does not report the Xray process name as exactly `xray`. The port may be held by the current `xray.service` MainPID and still be safe to reuse.
- Preventive rule: UDP/TCP port preflight must identify Xray ownership by process name, `xray.service` MainPID, and process executable/cmdline before blocking. Prefer `lsof -F` machine-readable output; if the local `lsof` output omits COMMAND and starts with PID/USER/FD, keep PID-based Xray detection instead of treating PID as a process name. Only non-Xray owners should require manual shutdown.
