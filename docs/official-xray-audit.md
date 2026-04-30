# official-xray-audit

本仓库的 Xray 配置判断优先级为：`Xray-core` 当前源码、官方 discussion/issue、官方文档、`Xray-examples`。第三方配置只作为问题线索，不作为默认配置依据。

## Source priority

- Xray-core `infra/conf/transport_internet.go`：JSON 配置字段、兼容别名、默认值和校验逻辑的硬约束。
- Xray-core `transport/internet/splithttp/config.proto`：XHTTP protobuf schema，确认 `headers` 是 `map<string,string>`，`mode` 默认由 core 处理。
- Xray-core `transport/internet/reality/config.proto`：Reality server/client 字段边界。
- Xray-core `infra/conf/hysteria.go` 与 `infra/conf/transport_internet.go`：Hysteria2 inbound 使用 `protocol=hysteria`、`version=2`，transport 使用 `network=hysteria`，旧 `up/down/congestion/udphop` 已迁移到 `finalmask.quicParams`。
- https://github.com/XTLS/Xray-core/discussions/4113：XHTTP 推荐使用原则，默认只填 `path`，Nginx 穿透优先使用 `grpc_pass`。
- https://github.com/XTLS/Xray-core/discussions/716：VMess/VLESS 分享 URI 规则，URL value 必须编码，Reality 使用 `pbk/sid/spx`，XHTTP 使用 `type=xhttp/path/host/mode`。
- https://github.com/XTLS/Xray-core/issues/5923、https://github.com/XTLS/Xray-core/issues/6036、https://github.com/XTLS/Xray-core/issues/6024：只作为兼容风险记录，不把未确认的实验参数写入默认模板。
- https://v2.hysteria.network/docs/developers/URI-Scheme/：Hysteria2 分享 URI 只携带连接必要信息，不携带带宽、ACL 或服务端 masquerade 配置。

## Decisions

- Reality 服务端模板只写服务端必需字段：`target`、`serverNames`、`privateKey`、`shortIds`。`publicKey` 不再写入服务端配置；分享时优先从旧配置读取，读取不到时用 `privateKey` 通过 Xray-core 推导。
- XHTTP 服务端模板只写 `path`。`mode=auto` 由 core 默认值承担；默认不写 `headers`，避免把数组型伪浏览器 header 写进 core 期望的 `map<string,string>` 字段。
- TLS 套餐的 XHTTP fallback 先进入本地 Nginx，再由 Nginx 使用 `grpc_pass` 转发到 XHTTP inbound，匹配 #4113 的 Nginx 建议。
- VLESS 分享链接由统一上下文生成，所有 query/fragment value 走 URL encode；Reality 链接带 `pbk`、有 shortId 时带 `sid`，并始终带 `spx=/`。
- VMess WS TLS 保留 legacy base64 JSON，同时追加官方 URI 格式，避免破坏旧客户端导入能力。
- Hysteria2 使用 Xray-core 内置 inbound，不生成 `apernet/hysteria` YAML。TCP/443 继续由 Nginx/Xray 使用，UDP/443 由 Hysteria2 使用；Brutal 带宽参数只在用户显式输入非 0 Mbps 时写入 `finalmask.quicParams.brutalUp/brutalDown`。
- Hysteria2 auth 跟随现有 UUID 用户；分享链接为 `hysteria2://<auth>@<domain>:443/?sni=<domain>#<name>`，所有动态值 URL encode，不写带宽参数。
- Hysteria2 的 SNI 和证书域名必须是用户控制并可签发证书的真实域名，默认复用现有 `domain`/`TLSDomain`。Reality 目标域名通常不是用户控制的域名，只能作为 masquerade proxy 内容源 fallback，不能作为 Hy2 证书域名。
- Hysteria2 masquerade 不使用固定第三方 URL；默认值按已有 Hy2 配置、Nginx 伪装站 upstream、Reality 目标 HTTPS 内容源的顺序推导，推导不到时要求用户手动输入。

## Manual checks

```bash
bash -n install.sh
find lib packaging -name "*.sh" -print0 | xargs -0 -n1 bash -n
bash -c 'source ./install.sh; declare -F xray_agent_main; declare -F menu; declare -F xray_agent_run_install_profile'
```

配置模板变更后，手工渲染 TLS、Reality、XHTTP、Nginx 和分享链接；对生成的 Xray JSON 执行 `jq empty`。如测试环境存在当前 Xray binary，再用该 binary 对临时配置执行配置测试。
