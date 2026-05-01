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
| `/etc/xray-agent/profiles` | 安装组合和协议选项 |
| `/etc/xray-agent/templates` | 脚本生成配置时使用的基础文件 |
| `/etc/xray-agent/backups` | 菜单生成的本机离线备份 |
| `/etc/xray-agent/tls` | TLS 证书和 acme 日志 |
| `/etc/xray-agent/xray` | Xray-core、geosite、geoip |
| `/etc/xray-agent/xray/conf` | Xray 拆分 JSON 配置 |
| `/etc/nginx/conf.d` | Nginx 站点配置 |

## 脚本管理范围

脚本会管理自己的运行目录、证书、Xray 配置和脚本托管的 Nginx 配置。一般用户不需要手动编辑这些文件；通过菜单修改会更安全，脚本也会在关键操作前做检查。

宝塔、1Panel、OpenResty、Caddy、Apache 等第三方站点配置不会被脚本自动改写。脚本只会检测它们是否存在，并给出接入建议。

## 备份建议

升级或迁移前优先使用菜单 `16.备份与恢复管理` 创建备份。备份包默认写入：

```text
/etc/xray-agent/backups
```

备份包包含 `/etc/xray-agent` 和脚本管理的 Nginx 配置。恢复前会先检查备份完整性、JSON 配置、Xray 配置和 Nginx 配置，避免把明显不可用的配置恢复到系统里。

如果需要手工备份，可以使用：

```bash
tar -czf /root/xray-agent-backup.tgz /etc/xray-agent /etc/nginx/conf.d
```

如果只想保留证书，至少备份：

```text
/etc/xray-agent/tls
```

## 现有网站和反代

菜单 `4.网站/反代管理` 只维护脚本自己的 Nginx 配置，不会自动重写宝塔、1Panel、Caddy、Apache 或其他复杂站点配置。

推荐做法是把已有真实网站放在本机端口上，例如 `http://127.0.0.1:8080`，再在菜单中注册为本机/自有网站。脚本会优先把浏览器访问转发到这个真实网站，并默认使用安装域名访问它。

已注册的本机/自有网站会作为统一伪装目标优先使用：TLS 浏览器访问会转发到该网站；Reality 新安装或重配时会优先建议该网站域名；Hysteria2 默认伪装 URL 也会优先使用同一个域名。已有 Reality 或 Hysteria2 配置会先询问是否保留，用户仍可手动输入自己的目标。

443 入口的 PROXY protocol 使用 `auto/on/off` 三种模式。默认 `auto` 会尽量开启；如果检测到已有 HTTPS 网站可能不兼容，就会关闭并提示原因。用户可以在菜单中切换，但切换前会看到受影响的后端。

HTTPS SNI 透传后端只适合高级场景。PROXY protocol 是 443 入口的全局开关，不能对不同 HTTPS 后端分别开关；未知后端会按不安全处理，避免把已有网站打坏。

## 手动修改提醒

不建议直接编辑 `/etc/xray-agent/xray/conf` 下的配置文件。菜单重新生成配置时，手工改动可能被覆盖。需要长期保留的改动应优先通过菜单完成。
