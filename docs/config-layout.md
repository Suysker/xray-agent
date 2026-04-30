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

Xray 配置模板按 Xray-core 当前源码字段收口：Reality 服务端模板只保留服务端字段，XHTTP 服务端模板只写必要 `path`，分享链接模板只表达稳定外部 URI/legacy JSON 格式。

运行时不新增 `state.json`；安装状态继续从 Xray/Nginx/acme 现有配置反推，反推逻辑集中在 `lib/runtime.sh`。
