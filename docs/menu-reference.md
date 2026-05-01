# 菜单参考

安装完成后运行 `vasma` 可以重新打开菜单。

## 安装

| 编号 | 功能 |
| --- | --- |
| 1 | 安装或重新安装 TLS 套餐：VLESS-TCP、VLESS-WS、VMess-WS、XHTTP、Hysteria2 |
| 2 | 安装或重新安装 Reality 套餐：VLESS-TCP Reality、XHTTP Reality，可选 Hysteria2 |

## 工具管理

| 编号 | 功能 |
| --- | --- |
| 3 | 账号管理：添加、删除、查看用户和分享链接 |
| 4 | 网站/反代管理：注册本机/自有网站 upstream、修改外部伪装站、管理受控 legacy HTTPS 后端 |
| 5 | 证书管理：申请、续签、删除、查看证书 |
| 6 | IPv4/IPv6 出站策略：按当前网络能力管理出站 |
| 7 | 黑名单和中国大陆 IP 策略 |
| 8 | WARP 分流和中国大陆域名/IP 策略 |
| 9 | 添加新端口 |
| 10 | 流量嗅探管理 |
| 11 | sockopt 进阶管理 |
| 12 | Hysteria2 管理：查看、重配、卸载、后续启用 |

## 版本与脚本

| 编号 | 功能 |
| --- | --- |
| 13 | 订阅管理：查看通用 URI/Base64、Clash/Mihomo YAML、当前协议支持状态和自定义规则源 |
| 14 | Xray-core 管理：升级、预览版、回退、启停、重启、更新 geosite/geoip |
| 15 | 更新脚本 |
| 16 | 备份与恢复管理：创建、查看、恢复本机离线备份 |
| 17 | 查看日志 |
| 18 | 卸载脚本 |

## 其他功能

| 编号 | 功能 |
| --- | --- |
| 19 | AdGuardHome 管理 |
| 20 | WARP 外部工具 |
| 21 | 内核管理和 BBR 优化 |
| 22 | 五网测速和 IPv6 测试 |
| 23 | 三网回程路由测试 |
| 24 | 流媒体解锁检测 |
| 25 | VPS 基本信息 |

菜单 3-16 会先展示当前安装状态、协议、证书、网络栈、网站 fallback 和关键端口，再显示当前环境可执行的动作。删除用户、修改网站 fallback、改路由、开新端口、卸载 Hysteria2、恢复备份等操作会要求二次确认。

订阅管理的 Clash/Mihomo YAML 覆盖 VLESS TCP TLS、VLESS WS TLS、VMess WS TLS、VLESS TCP Reality、VLESS XHTTP TLS/Reality 和 Hysteria2。内置规则源维护在 `profiles/subscription/rules.json`；菜单添加的自定义规则会保存到 `profiles/subscription/custom_rules.json`，升级脚本不会覆盖该文件。

网站/反代管理只维护脚本托管的 `alone.conf`、`alone.stream` 和反代注册文件。它可以注册本机 HTTP fallback、登记 legacy HTTPS SNI 后端、查看现有网站/面板接入建议，并切换前门 PROXY protocol 的 `auto/on/off` 模式。

切换前门 PROXY protocol 前会展示受影响的 Xray TLS/Reality inbound 和所有 HTTPS 透传后端。确认后会同步重渲染 Nginx stream，并更新 Xray inbound 的 `acceptProxyProtocol`。

备份与恢复管理会把 `/etc/xray-agent`、脚本托管的 Nginx 配置和 manifest 打包到 `/etc/xray-agent/backups`。恢复前会校验 manifest、文件校验和、JSON 和可用的 Xray/Nginx 配置；恢复前会自动再创建一份当前状态备份。
