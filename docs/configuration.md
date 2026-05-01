# 配置与目录

默认运行目录为：

```text
/etc/xray-agent
```

## 主要目录

| 路径 | 说明 |
| --- | --- |
| `/etc/xray-agent/install.sh` | 管理入口 |
| `/etc/xray-agent/lib` | 脚本运行模块 |
| `/etc/xray-agent/profiles` | 安装组合、协议、路由描述 |
| `/etc/xray-agent/templates` | Xray、Nginx、systemd、分享链接模板 |
| `/etc/xray-agent/backups` | 菜单生成的本机离线备份 |
| `/etc/xray-agent/tls` | TLS 证书和 acme 日志 |
| `/etc/xray-agent/xray` | Xray-core、geosite、geoip |
| `/etc/xray-agent/xray/conf` | Xray 拆分 JSON 配置 |
| `/etc/nginx/conf.d` | Nginx 站点配置 |

## 模板原则

模板只放完整配置文件、重要配置块和稳定外部格式，例如：

- Xray inbound、outbound、基础配置。
- Nginx 站点配置。
- systemd unit。
- 分享链接格式。

一行默认值、小数组、cron 行、包源行、临时 routing rule 不单独做模板，避免配置被拆得过碎。

## 备份建议

升级或迁移前优先使用菜单 `16.备份与恢复管理` 创建备份。备份包默认写入：

```text
/etc/xray-agent/backups
```

备份包包含 `/etc/xray-agent`、脚本托管的 Nginx 配置和 `manifest.json`。`manifest.json` 会记录版本、时间、域名、端口、协议和文件校验信息；恢复前会先做 manifest、校验和、JSON、Xray 和 Nginx 配置检查。

如果需要手工备份，可以使用：

```bash
tar -czf /root/xray-agent-backup.tgz /etc/xray-agent /etc/nginx/conf.d
```

如果只想保留证书，至少备份：

```text
/etc/xray-agent/tls
```

## 现有网站和反代

菜单 `4.网站/反代管理` 只维护脚本托管的 `alone.conf` 和 `alone.stream`，不会自动重写宝塔、1Panel、Caddy、Apache 或其他复杂站点配置。

推荐做法是把已有真实网站迁到本机 upstream，例如 `http://127.0.0.1:8080`，再在菜单中注册为本机/自有网站 fallback。脚本会把浏览器探测流量转发到该 upstream，并默认保留安装域名作为 Host。

已注册的本机/自有网站会作为统一伪装目标优先使用：TLS 的浏览器 fallback 继续转发到该 upstream；Reality 新安装/重配时会把该站点 Host 建议为默认 `target` 和 `serverNames`；Hysteria2 默认伪装 URL 也优先使用同一个站点域名。已有 Reality 或 Hysteria2 历史配置会先询问是否保留，用户仍可手动覆盖。

前门 PROXY protocol 使用 `auto/on/off` 三种模式。`auto` 会优先保留已有 `alone.stream` 的开关状态；没有历史配置时，纯净机、仅 HTTP fallback、或所有已注册 HTTPS 透传后端都声明 `proxy_protocol=supported` 才默认开启。检测到普通 HTTPS 后端、第三方面板站点或未知/不支持的 HTTPS 透传后端时，默认关闭。

legacy HTTPS SNI 后端只适合高级场景。它们和 Xray 共用同一个 Nginx stream 前门，PROXY protocol 是全局开关，不能按单个后端混用；未知后端会按不安全处理，避免把已有网站打坏。

## 手动修改提醒

不建议直接编辑 `/etc/xray-agent/xray/conf` 下的配置文件。菜单重新渲染配置时，手工改动可能被覆盖。需要长期保留的改动应优先通过菜单、profile 或模板完成。
