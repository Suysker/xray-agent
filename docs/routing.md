# routing

- 基础出站顺序由 `profiles/routing/*.profile` 描述，默认 profile 为 `ipv4_default`。
- `lib/routing.sh` 根据 routing profile 渲染 `10_ipv4_outbounds.json`，并负责 IPv6、WARP、黑名单、CN blackhole、规则/出站幂等删除。

- 保留 WARP 分流
- 保留 IPv6 优先 / IPv4 优先切换
- 保留黑名单和 CN blackhole
- 规则与 outbounds 由 `lib/routing.sh` 管理
