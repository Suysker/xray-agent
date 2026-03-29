# external-tools

- 菜单 `17` -> `lib/external/warp_menu.sh`
- 菜单 `18` -> `lib/external/kernel_bbr.sh`
- 菜单 `19` -> `lib/external/hysteria_oneclick.sh`
- 菜单 `20` -> `lib/external/hyperspeed.sh`
- 菜单 `21` -> `lib/external/backtrace.sh`
- 菜单 `22` -> `lib/external/unlock_media.sh`
- 菜单 `23` -> `lib/external/vps_info.sh`

这些菜单只做外部脚本调用，入口已从 `install.sh` 内嵌实现迁移到独立模块。

- 17 -> warp 菜单
- 18 -> 内核与 BBR
- 19 -> hysteria 一键
- 20 -> hyperspeed
- 21 -> backtrace
- 22 -> 流媒体解锁
- 23 -> VPS 信息
