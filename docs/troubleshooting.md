# 故障排查

## 安装失败

先确认：

- 是否使用 root 用户。
- 系统是否为 Debian/Ubuntu 或兼容发行版。
- 服务器是否能访问 GitHub、acme 服务和 Xray-core release。
- TCP/80、TCP/443 是否被其他服务占用。
- 云防火墙和本机防火墙是否放行对应端口。

建议使用纯净系统安装。如果曾安装过其他代理脚本或自编译 Nginx，先确认端口和配置没有冲突。

## 证书申请失败

常见原因：

- 域名 A/AAAA 没有解析到当前服务器。
- Cloudflare 开启代理后影响 HTTP-01 验证。
- TCP/80 没有放行。
- DNS TXT 记录未生效。
- DNS API 密钥权限不足。
- CA 限流。

可查看：

```text
/etc/xray-agent/tls/acme.log
```

通配证书、无公网入口或 80 端口不可用时，优先使用 DNS-01。

## Xray 启动失败

菜单重启 Xray 前会先执行配置测试。失败时优先检查：

- `/etc/xray-agent/xray/conf` 下 JSON 是否完整。
- 证书文件是否存在。
- 当前 Xray-core 版本是否支持配置中的字段。
- 新端口是否被占用。

可以通过菜单 `14.Xray-core 管理` 升级 Xray-core 正式版。

## 访问网站间歇性卡顿

如果服务器同时运行 AdGuardHome、dnsmasq、SmartDNS 等本机 DNS 服务，Xray 可以继续使用 `localhost` DNS，让代理流量也经过广告过滤。但广告或遥测规则可能把部分域名解析成 `0.0.0.0`、`::` 或本机地址。如果 Xray 继续按这个结果拨号，就会出现页面资源长时间等待、TLS 握手失败或连接超时。

默认安装会保留 `localhost` DNS 和 `UseIP`。为避免正常域名的 A 记录可用、AAAA 记录却被 AdGuardHome 返回为 `::` 时被误判为黑洞，建议把 AdGuardHome 的拦截响应模式设为 `nxdomain` 或 `refused`，让被过滤请求以 DNS 错误结束，而不是返回假 IP。排查已有安装时可检查：

```bash
jq . /etc/xray-agent/xray/conf/11_dns.json
jq . /etc/xray-agent/xray/conf/09_routing.json
getent ahostsv4 c.bing.com
getent ahostsv4 mobile.events.data.microsoft.com
dig +short @127.0.0.1 www.bing.com AAAA
```

如果这些域名在服务器上解析为 `0.0.0.0`、`127.0.0.1`、`::` 或 `::1`，应确认 `/etc/xray-agent/xray/conf/09_routing.json` 里存在把这些地址送到 `blackhole-out` 的规则。如果正常域名的 A 记录正常但 AAAA 记录被过滤为 `::`，优先调整 AdGuardHome 的 `blocking_mode`，不要为了规避误伤而绕过 `localhost` DNS 或改掉 `UseIP`。

如果 AdGuardHome 管理菜单提示 `/etc/resolv.conf: Operation not permitted`，通常是该文件被锁定、所在挂载只读，或由系统 DNS 服务接管。脚本会先尝试解除常见锁定；仍失败时不会再显示“系统 DNS 已指向 AdGuardHome”。可以检查 `lsattr /etc/resolv.conf`、`ls -l /etc/resolv.conf` 和 `findmnt /etc/resolv.conf /etc`。

## Xray-core 升级失败

如果 GitHub Release API 被限流或网络返回异常，脚本会停止升级并保留当前 Xray-core。稍后重试，或先确认服务器可以稳定访问 `api.github.com` 和 `github.com/XTLS/Xray-core/releases`。

## Nginx 启动失败

修改回落站点、切换 PROXY protocol 或更新 Nginx 配置后，脚本会先检查配置。失败时检查：

- 是否安装了系统包管理器提供的 Nginx。
- 是否已有其他站点配置占用 80/443。
- 回落站点 URL 是否有效。
- Nginx 是否支持当前配置需要的模块。
- 菜单中显示的 PROXY protocol 状态是否符合当前后端能力。

宝塔、1Panel、OpenResty、Caddy、Apache 等第三方前端只会被检测，不会被脚本自动改写。已有 HTTPS 站点如果不支持 PROXY protocol，应保持该模式关闭，或先把真实网站迁到本机端口后在菜单中注册。

## 分享链接不可用

检查顺序：

1. 客户端是否支持对应协议和字段。
2. 域名解析是否正确。
3. 端口是否放行。
4. Reality 链接是否包含 `pbk`，有 shortId 时是否包含 `sid`。
5. Hysteria2 是否放行 UDP/443。
6. 当前 Xray-core 是否为正式版且支持对应能力。
7. 如果启用了 443 入口分流，确认菜单中的 PROXY protocol 状态没有提示冲突。

VMess WS TLS 主要用于旧客户端兼容。新客户端优先使用 VLESS、Reality、XHTTP 或 Hysteria2。

## Hysteria2 无法连接

- 确认云防火墙放行 UDP/443。
- 确认本机防火墙放行 UDP/443。
- Hysteria2 重配时，如果 UDP/443 owner 是当前 `xray.service`，这是可复用状态；如果提示外部进程占用，则需要先停止该外部进程或改端口。
- 如果启用了端口跳跃，确认云防火墙放行分享链接里的 UDP 端口范围，并确认客户端支持 Hysteria2 多端口格式。脚本会在本机创建 REDIRECT，把跳跃端口转到 UDP/443；如果菜单提示 REDIRECT 写入失败，端口跳跃配置会回滚。
- 确认证书域名是自己控制的真实域名。
- 多公网 IP 或 WARP 默认路由环境中，确认 UDP 回复路径没有异常。
- 客户端导入时不要手动加入服务端带宽参数。

## WARP 或 IPv6 异常

- 进入菜单 `6` 或 `8` 查看当前网络能力提示。
- WARP 接口必须存在并且有 IPv4 或 IPv6 地址。
- WARP 已接管默认路由时，公网探测结果可能不是服务器真实入站 IP。
- IPv6-only 环境中，请确认域名 AAAA 解析和云防火墙 IPv6 规则。
