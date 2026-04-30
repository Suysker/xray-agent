# certificates

- `lib/tls.sh` 负责 ACME 服务商选择、邮箱注册、证书申请、更新、删除、Reality 目标域名和证书菜单。
- `lib/system.sh` 负责 `RenewTLS` 定时任务。
- 证书文件统一存放在 `/etc/xray-agent/tls`。
- Hysteria2 复用同目录下的 TLS 证书；Reality-only 环境启用 Hysteria2 时也通过现有证书流程复用或申请证书。Hysteria2 的 SNI/证书域名必须是用户控制的真实域名，默认回车使用当前 Xray TLS 域名，不使用 Reality 目标域名签证书。

- 菜单 `5.证书管理` 进入后会展示证书库存：`/etc/xray-agent/tls/*.crt|key`、`~/.acme.sh/*_ecc`、剩余天数、私钥是否匹配、acme 记录是否存在。
- 智能申请向导会先规范化域名，检查 A/AAAA 与当前公网候选、网络栈、TCP/80 和 TCP/443 占用，再推荐 HTTP-01 standalone 或 DNS-01。通配证书、解析不匹配、无公网、80 端口被非 Nginx 服务占用时默认推荐 DNS-01。
- DNS-01 仍只保留主线能力：Cloudflare、DNSPod、Aliyun、自定义 dns 类型和手动 TXT。手动 TXT 会显示 `_acme-challenge`、value 和 `dig` 检测命令。
- 续签默认只处理到期或 14 天内临期证书；强制续签全部证书需要二次确认，避免触发 CA 限流。
- `xray_agent_cert_explain_failure` 会按 acme 日志提示邮箱错误、解析/端口验证失败、TXT 未生效、CA 限流、EAB/API 错误等常见原因。
- Reality 目标域名与 serverNames 仍在 `lib/tls.sh` 管理。
