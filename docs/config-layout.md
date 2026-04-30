# config-layout

- `/etc/xray-agent/install.sh`：bootstrap、模块加载和主入口调用
- `/etc/xray-agent/lib`：运行时模块副本
- `/etc/xray-agent/templates`：重要配置模板目录，只放完整配置文件、重要配置块和稳定外部格式
- `/etc/xray-agent/profiles`：profile 目录
- `/etc/xray-agent/docs`：随包文档
- `/etc/xray-agent/packaging`：升级与卸载辅助
- `/etc/xray-agent/tls`：证书与 acme 日志
- `/etc/xray-agent/xray`：Xray 核心与 geodata
- `/etc/xray-agent/xray/conf`：拆分 JSON 配置

单独下载 `install.sh` 时，入口会先 bootstrap 上述完整目录，再执行 `/etc/xray-agent/install.sh`。

仓库和运行时都不保留 `verify/` 或 `scripts/check.sh`；配置可读源集中在 `templates/`，但一行默认值、小 JSON 片段、cron 行和包源行不进入模板目录。

Xray 配置模板按 Xray-core 正式 release 字段收口：Reality 服务端模板只保留服务端字段并可写 `mldsa65Seed`，XHTTP 服务端模板只写必要 `path`，Hysteria2 模板使用 `protocol=hysteria`、`network=hysteria`、TLS 证书、可选 `echServerKeys` 和可选 `finalmask.quicParams`，分享链接模板只表达稳定外部 URI/legacy JSON 格式。

VLESS Encryption 的客户端 `encryption` 不额外落盘；运行时从 VLESS inbound 的 `settings.decryption` 通过 Xray-core `x25519`/`mlkem768` 命令反推分享值。Reality `pqv` 同样从 `mldsa65Seed` 反推，TLS `ech` 从 `echServerKeys` 反推，因此不需要新增 `state.json`。

Hysteria2 运行时默认值由代码按当前环境推导，不拆成 tiny tpl：连接域名/SNI/证书域名默认使用已有 `domain`/`TLSDomain`；masquerade URL 默认顺序是已有 Hy2 配置、Nginx `alone.conf` 的 `proxy_pass`、Reality 目标域名 HTTPS 内容源，最后才要求手动输入。

运行时不新增 `state.json`；安装状态继续从 Xray/Nginx/acme 现有配置反推，反推逻辑集中在 `lib/runtime.sh`。

网络状态也不落盘。`lib/network.sh` 每次运行时探测默认路由、公网地址、本机回环和 WARP 接口能力；模板只接收推导后的监听地址、内部 upstream、fallback `dest` 和 outbound strategy。
