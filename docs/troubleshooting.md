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

可以通过菜单 `13.core管理` 升级 Xray-core 正式版。

## Nginx 启动失败

更换伪装站或渲染 Nginx 配置后会执行 `nginx -t`。失败时检查：

- 是否安装了系统包管理器提供的 Nginx。
- 是否已有其他站点配置占用 80/443。
- 伪装站 URL 是否有效。
- Nginx 是否支持当前配置需要的模块。

不建议在同一台机器上混用多个脚本管理 Nginx。

## 分享链接不可用

检查顺序：

1. 客户端是否支持对应协议和字段。
2. 域名解析是否正确。
3. 端口是否放行。
4. Reality 链接是否包含 `pbk`，有 shortId 时是否包含 `sid`。
5. Hysteria2 是否放行 UDP/443。
6. 当前 Xray-core 是否为正式版且支持对应能力。

VMess WS TLS 主要用于旧客户端兼容。新客户端优先使用 VLESS、Reality、XHTTP 或 Hysteria2。

## Hysteria2 无法连接

- 确认云防火墙放行 UDP/443。
- 确认本机防火墙放行 UDP/443。
- 确认证书域名是自己控制的真实域名。
- 多公网 IP 或 WARP 默认路由环境中，确认 UDP 回复路径没有异常。
- 客户端导入时不要手动加入服务端带宽参数。

## WARP 或 IPv6 异常

- 进入菜单 `6` 或 `8` 查看当前网络能力提示。
- WARP 接口必须存在并且有 IPv4 或 IPv6 地址。
- WARP 已接管默认路由时，公网探测结果可能不是服务器真实入站 IP。
- IPv6-only 环境中，请确认域名 AAAA 解析和云防火墙 IPv6 规则。
