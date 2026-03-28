# local-mode

本地模式菜单提供两项能力：

- `local_tun`：生成 TUN inbound 与 process routing 示例
- `browser_dialer`：输出使用说明，提醒浏览器参与和回环风险

使用原则：

- TUN 不会自动修改系统路由
- 需要手动设置默认路由或策略路由
- 建议只代理明确的进程名，避免自身回环
- Browser Dialer 只建议在本地场景中使用
