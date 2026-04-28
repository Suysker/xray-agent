# external-tools

- 菜单 `17` -> `lib/external.sh` -> `xray_agent_external_warp_menu`
- 菜单 `18` -> `lib/external.sh` -> `xray_agent_external_kernel_bbr`
- 菜单 `19` -> `lib/external.sh` -> `xray_agent_external_hysteria_oneclick`
- 菜单 `20` -> `lib/external.sh` -> `xray_agent_external_hyperspeed`
- 菜单 `21` -> `lib/external.sh` -> `xray_agent_external_backtrace`
- 菜单 `22` -> `lib/external.sh` -> `xray_agent_external_unlock_media`
- 菜单 `23` -> `lib/external.sh` -> `xray_agent_external_vps_info`

这些菜单只做外部脚本调用，入口已从 `install.sh` 内嵌实现迁移到独立模块。

- 17 -> warp 菜单
- 18 -> 内核与 BBR
- 19 -> hysteria 一键
- 20 -> hyperspeed
- 21 -> backtrace
- 22 -> 流媒体解锁
- 23 -> VPS 信息
