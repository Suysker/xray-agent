# certificates

- `lib/tls/acme.sh` 负责 ACME 服务商选择、邮箱注册、证书申请方式。
- `lib/tls/certs.sh` 负责 Nginx 域名输入、随机路径、证书安装、更新、删除和证书菜单。
- `lib/system/cron.sh` 负责 `RenewTLS` 定时任务。
- 证书文件统一存放在 `/etc/xray-agent/tls`。

- ACME 申请逻辑在 `lib/tls/acme.sh`
- 证书安装、续签、删除在 `lib/tls/certs.sh`
- Reality 目标域名与 serverNames 在 `lib/tls/reality.sh`
