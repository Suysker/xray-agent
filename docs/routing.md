# routing

- 基础出站顺序由 `profiles/routing/*.profile` 描述，默认 profile 为 `ipv4_default`。
- `lib/routing/base.sh` 根据 routing profile 渲染 `10_ipv4_outbounds.json`。
- `lib/routing/ipv6.sh` 负责 IPv6 域名分流和全局 IPv6/IPv4 优先切换。
- `lib/routing/warp.sh` 负责 WARP 分流与 CN 域名/IP 分流。
- `lib/routing/blacklist.sh` 负责黑名单域名和中国大陆 IP 黑洞规则。
- `lib/routing/rules.sh` 和 `lib/routing/outbounds.sh` 负责规则/出站的幂等删除。

- 保留 WARP 分流
- 保留 IPv6 优先 / IPv4 优先切换
- 保留黑名单和 CN blackhole
- 规则与 outbounds 由 `lib/routing/*` 管理
