# 网络与路由

xray-agent 会在运行时探测系统网络能力，包括默认 IPv4/IPv6 路由、公网 IPv4/IPv6、本机回环地址、WARP 接口和 WARP 是否接管默认路由。

## 默认策略

- IPv4-only：默认使用 IPv4 可用基线，不显示不适用的 IPv6 动作。
- IPv6-only：默认使用 IPv6 可用基线，内部回环和 DNS 接管优先使用 IPv6。
- 双栈：默认保持 IPv4 优先，可在菜单中切换 IPv6 优先或添加 IPv6 域名出站。
- 无可用默认路由：阻止新增出站策略，只显示诊断信息。

默认安装不会自动启用 IPv6 或 WARP 分流，需要用户在菜单中手动开启。

## 多公网 IP

TLS、WS、XHTTP、Hysteria2 分享链接优先使用域名。Reality 场景需要选择具体公网入站地址：

- 只有一个公网 IP 时自动使用。
- 多个公网 IP 时提示选择。
- 无法探测真实公网地址时，提示用户手动输入。

如果 WARP 已接管默认路由，公网探测结果可能是 WARP 出口 IP；脚本不会把 WARP 出口当作 Reality 入站地址。

## WARP 分流

菜单 `8.WARP分流及中国大陆域名+IP` 会显示当前 WARP 接口能力：

- WARP IPv4-only：只生成 IPv4 可用出站。
- WARP IPv6-only：只生成 IPv6 可用出站。
- WARP 双栈：生成双栈出站。
- WARP 已接管默认路由：脚本会提示系统默认流量已经走 WARP，Xray 绑定接口只是显式指定。

WARP 出站会使用检测到的真实接口名，不只按接口名称猜测。

## 黑名单和 CN 策略

菜单 `7.阻止访问黑名单及中国大陆IP` 可用于管理黑名单和中国大陆 IP 策略。菜单会展示当前规则数量和出站状态，避免重复添加规则。

## 内部回环

脚本会根据系统能力选择内部监听和回环地址：

- IPv4 可用时优先使用 `127.0.0.1`。
- IPv6-only 或无 IPv4 回环时使用 `::1`，Nginx upstream 使用 `[::1]` 格式。

Xray fallback、Nginx upstream、dokodemo 转发和 AdGuardHome DNS 接管都使用同一套策略。
