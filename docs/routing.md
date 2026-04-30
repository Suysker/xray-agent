# routing

- 网络能力由 `lib/network.sh` 动态探测：默认路由 IPv4/IPv6、公网 IPv4/IPv6、本机回环 IPv4/IPv6、WARP/wgcf/warp 接口、接口地址，以及 WARP 是否接管 IPv4/IPv6 默认路由；运行时不新增 `state.json`。
- 基础出站顺序由 `profiles/routing/*.profile` 描述。IPv4-only 和双栈默认使用 `ipv4_default`，IPv6-only 默认使用 `ipv6_first`，避免生成不可用 IPv4 基线；`hasIPv4/hasIPv6` 只表达默认路由能力，不再混合公网探测结果。
- 默认安装不自动启用 IPv6/WARP 分流。菜单 `6.IPv4/IPv6出站策略` 和 `8.WARP分流` 进入前会显示统一状态头、当前网络探测结果和现有规则数量，并只显示当前网络栈可执行的动作。
- 多公网 IP 场景下，TLS/WS/XHTTP/Hysteria2 分享继续域名优先；Reality 分享才选择具体公网地址，只有一个自动使用，多个时提示选择。
- 如果 WARP 已接管某个 IP family 的默认路由，该 family 的 `curl` 公网结果可能是 WARP 出口 IP，不会作为 Reality 入站地址候选；双栈默认都走 WARP 时需要手动输入服务器真实入站公网 IP 或域名。
- WARP 分流使用探测到的真实接口名，并要求接口至少有 IPv4 或 IPv6 地址。探测结果会区分“专用接口”和“默认路由已走 WARP”，并按 WARP IPv4-only、IPv6-only、双栈能力渲染对应 outbound `domainStrategy`。
- 内部回环地址由网络能力统一推导：IPv4 可用优先 `127.0.0.1`，IPv6-only 或无 IPv4 loopback 时使用 `::1`/`[::1]`；Xray fallback、Nginx upstream、dokodemo 转发和 AdGuard DNS 都走这个策略。
- `lib/routing.sh` 继续负责 IPv6、WARP、黑名单、CN blackhole、规则/出站幂等删除；outbound 模板仍集中在 `templates/xray/outbounds`。
