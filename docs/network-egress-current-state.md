# IPv4/IPv6 与 WARP 出站现状基线

> 状态：实施前基线，保留用于需求和回归对照；不代表当前代码能力
>
> 基线日期：2026-08-23
> 适用范围：`xray-agent v3.2.0`、当前 `master` 分支及 Xray-core `v25.6.8+` 相关出站逻辑

本文记录 xray-agent 当前对原生 IPv4、原生 IPv6、WARP IPv4、WARP IPv6、系统默认路由和 Xray 分流的真实支持边界。它是后续网络出站重构的原始需求与验收基线，不是目标能力说明。

实机信息只使用“节点 A / 节点 B”表示，不记录公网 IP、登录凭据、WARP 密钥或账户信息。

目标方案及当前实施状态见 [IPv4/IPv6 与 WARP 四出口架构方案](network-egress-design.md)。当前使用方式见 [网络与路由](network-routing.md)。

## 1. 用户目标

需要覆盖以下长期使用方式：

1. 原生 IPv4-only VPS，通过 WARP 补充 IPv6。
2. 原生 IPv6-only VPS，通过 WARP 补充 IPv4。
3. 原生 IPv4/IPv6 双栈 VPS，同时安装 WARP。
4. 可以明确选择原生 IPv4、原生 IPv6、WARP IPv4 或 WARP IPv6。
5. 可以区分系统全局 WARP、仅 Xray 全局出站和按规则分流。
6. TCP 双栈域名可以选择首选地址族，并在条件满足时自动回退。
7. UDP、IP 字面量和单地址族域名不作错误的自动回退承诺。
8. WARP 接管默认路由时，服务器公网入站回程不能被破坏。

## 2. 三个容易混淆的控制层

| 控制层 | 实际含义 | 当前入口 |
| --- | --- | --- |
| Linux 系统默认路由 | 影响 `curl`、包管理器、Xray 等所有本机进程 | 菜单 `20.WARP` 调用外部脚本 |
| Xray 默认出站 | 影响未命中路由规则的代理流量；Xray 默认使用第一个 outbound | 菜单 `6.IPv4/IPv6 出站策略` |
| Xray 规则分流 | 只影响命中的域名、IP 或其他路由条件 | 菜单 `7`、菜单 `8` |

“IPv4/IPv6 优先”只描述地址族顺序；“原生/WARP 出口”描述实际出口身份。二者不是同一个维度。

## 3. 当前代码模型

当前实现包含以下主要路径：

| 路径 | 当前职责 |
| --- | --- |
| `lib/network.sh` | 探测 IPv4/IPv6 默认接口、公网地址、WARP 接口及 WARP 默认路由模式 |
| `lib/routing.sh` | 生成基础出站、切换 IPv4/IPv6 顺序、添加 IPv6/WARP/CN 规则 |
| `templates/xray/outbounds/freedom_ipv4*.json.tpl` | IPv4 强制或 IPv4 优先 Freedom 出站 |
| `templates/xray/outbounds/freedom_ipv6*.json.tpl` | IPv6 强制或 IPv6 优先 Freedom 出站 |
| `templates/xray/outbounds/warp_out.json.tpl` | 绑定一个 WARP 接口的通用出站 |
| `templates/xray/outbounds/cn_out.json.tpl` | 绑定 WARP 接口的 CN 出站 |
| `lib/external.sh` | 下载并运行外部 WARP 管理脚本 |

### 3.1 已确认的维护边界

WARP 安装实现继续使用当前上游外部脚本，不复制、不分叉，也不由 xray-agent 维护其注册、账户、Endpoint、WireGuard 基础配置和全局模式实现。

xray-agent 自己维护网络集成层：

- 调用外部脚本并处理返回结果。
- 从实时接口、地址、路由和策略规则识别原生/WARP 能力。
- 管理仅属于 xray-agent 的补充策略路由，不改写外部脚本生成的配置和规则。
- 构建出口目录，生成 Xray outbound、默认出站和规则分流。
- 验证、解释、备份和清理由 xray-agent 自己创建的网络状态。

外部脚本的输出是网络集成层的输入，实时 Linux 内核状态是最终事实来源。

当前网络探测可以识别：

- 是否存在经过真实公网请求验证的 IPv4/IPv6 有效默认路径。
- WARP 接口是否具有 IPv4、IPv6 或双栈地址。
- WARP 是否接管 IPv4 默认路由、IPv6 默认路由或两者。
- 绑定具体接口后的公网地址族是否可达，以及实际出口身份是原生还是 WARP。

当前路由模型只定义 `IPv4-out`、`IPv6-out` 和一个通用 `warp-out`，没有把“地址族”和“出口提供者”拆开。因此它无法完整表达四个独立出口。

## 4. 两个代表节点

### 4.1 第一台 VPS（节点 A）：原生 IPv4 + WARP IPv6

实施前只读实机检查确认：

- 原生公网出口只有 IPv4。
- IPv4 默认接口为原生网卡。
- IPv6 默认接口为 WARP。
- WARP 接口自身具有 IPv4 和 IPv6 地址。
- Xray-core 为 `v26.5.9`。
- 已部署 Xray 配置仍使用旧的 `UseIPv4` / `UseIPv6` 强制单栈出站。
- 未匹配规则的流量默认走原生 IPv4。
- CN 规则绑定 WARP 接口，但使用 `UseIP`，不保证 WARP 地址族。

当前实际行为：

```text
默认流量        -> 原生 IPv4
IPv6-out 规则   -> WARP IPv6
cn-out 规则     -> WARP 接口，由当前解析和核心行为选择地址族
```

该节点的旧配置可以强制选择两个地址族，但没有首选地址族失败后的自动回退。

2026-08-23 已手工按新模型收口在线配置：默认 TCP/UDP 保持原生 IPv4，原有区域规则改为 TCP 使用 `warp-auto-out` 的 IPv4 优先竞速、UDP 明确使用 `warp-ipv4-out`。候选配置先经过 Xray 原生测试再原子替换；WireGuard、Linux 路由和策略规则前后未变化，Xray 重启后保持 active。该操作是在线机器的独立人工处理，不构成仓库中的旧安装迁移功能。

### 4.2 第二台 VPS（节点 B）：原生 IPv6 + WARP IPv4

服务器内部只读检查与绑定接口公网探测确认：

```text
IPv4 默认路由  -> WARP IPv4
IPv6 默认路由  -> 原生 IPv6
```

- 原生接口具有云平台私网 IPv4 地址和主路由，但绑定该接口访问公网失败，因此 `native-ipv4-out` 必须标记为不可用。
- 原生 IPv6 绑定接口公网实测可用。
- WARP 接口的 IPv4、IPv6 绑定公网实测都返回 WARP 身份，因此 `warp-ipv4-out`、`warp-ipv6-out` 和 `warp-auto-out` 可用。
- `ip route get ... oif wgcf from ...` 对 WARP IPv6 返回原生接口，但 Xray 同类的绑定接口请求实际成功走 WARP；该命令不能单独模拟 `SO_BINDTODEVICE`。
- Xray-core 为 `v26.5.9`，实施前仍使用旧的 `IPv4-out` / `IPv6-out` / `warp-out` 配置。

2026-08-23 已手工按新模型收口在线配置：默认 TCP 使用 `system-auto-out` 且 IPv4 优先，默认 UDP 使用 `warp-ipv4-out`，原有区域规则的 TCP 使用 `warp-auto-out`、UDP 使用 `warp-ipv4-out`。临时本机 SOCKS 实测双栈目标返回 WARP 身份，IPv6-only 目标返回 HTTP 204；WireGuard、Linux 路由和策略规则前后未变化。该操作同样不构成仓库中的迁移逻辑。

按当前代码，脚本会把它识别为可用双栈，并默认选择 `IPv4-out`。这意味着新安装默认更可能优先使用 WARP IPv4，而不是原生 IPv6。菜单可以调整出站顺序，但仍受本文第 7.1 节的运行时缺陷影响。

## 5. 请求类型决定能力上限

| 请求类型 | 能否做地址族优先/回退 | 原因 |
| --- | --- | --- |
| TCP、目标域名同时有 A/AAAA | 条件满足时可以 | Happy Eyeballs 可以竞速多个解析地址 |
| TCP、目标域名只有 A | 不可以切换到 IPv6 | 没有 IPv6 目标地址 |
| TCP、目标域名只有 AAAA | 不可以切换到 IPv4 | 没有 IPv4 目标地址 |
| TCP、目标为 IPv4 字面量 | 不可以 | 目标已经固定为 IPv4 |
| TCP、目标为 IPv6 字面量 | 不可以 | 目标已经固定为 IPv6 |
| UDP | 不能承诺 Happy Eyeballs | Xray Freedom 的 Happy Eyeballs 只处理 TCP |

即使网络具备四个出口，也不能把所有请求宣传成“IPv4/IPv6 自动回退”。

## 6. 十五种系统路由组合

符号说明：

- `N4`：原生 IPv4。
- `N6`：原生 IPv6。
- `W4`：WARP IPv4。
- `W6`：WARP IPv6。
- “WARP 专用接口”：WARP 不接管该地址族的系统默认路由，只能通过接口绑定或策略路由使用。

下表假设 WARP 接口自身是双栈；WARP 单栈情况见第 6.1 节。

| 原生网络 | WARP 系统模式 | Xray 基础出站的实际映射 | 当前支持结论 |
| --- | --- | --- | --- |
| IPv4-only | 无 WARP | `IPv4=N4` | 支持单栈 |
| IPv6-only | 无 WARP | `IPv6=N6` | 支持单栈 |
| 双栈 | 无 WARP | `IPv4=N4`、`IPv6=N6` | 地址族可选；自动回退受第 7.1 节影响 |
| IPv4-only | WARP 专用接口 | 基础=`N4`；WARP 规则=`W4/W6` | 可按域名使用 WARP，不能选择 WARP 地址族或设为明确默认出口 |
| IPv6-only | WARP 专用接口 | 基础=`N6`；WARP 规则=`W4/W6` | 同上 |
| 双栈 | WARP 专用接口 | 基础=`N4/N6`；WARP 规则=`W4/W6` | 可在原生双栈和通用 WARP 规则间分流，不能独立选择四出口 |
| IPv4-only | WARP 接管 IPv4 | `IPv4=W4` | 无法从 Xray 菜单重新选择 `N4` |
| IPv6-only | WARP 接管 IPv4 | `IPv4=W4`、`IPv6=N6` | 节点 B 类型；可间接选地址族，自动回退不可靠 |
| 双栈 | WARP 接管 IPv4 | `IPv4=W4`、`IPv6=N6` | `N4` 不能作为独立出站选择 |
| IPv4-only | WARP 接管 IPv6 | `IPv4=N4`、`IPv6=W6` | 节点 A 类型；可间接选地址族，自动回退不可靠 |
| IPv6-only | WARP 接管 IPv6 | `IPv6=W6` | 无法从 Xray 菜单重新选择 `N6` |
| 双栈 | WARP 接管 IPv6 | `IPv4=N4`、`IPv6=W6` | `N6` 不能作为独立出站选择 |
| IPv4-only | WARP 接管双栈 | `IPv4=W4`、`IPv6=W6` | `N4` 不能作为独立出站选择 |
| IPv6-only | WARP 接管双栈 | `IPv4=W4`、`IPv6=W6` | `N6` 不能作为独立出站选择 |
| 双栈 | WARP 接管双栈 | `IPv4=W4`、`IPv6=W6` | `N4/N6` 都不能作为独立出站选择 |

### 6.1 WARP 接口地址能力

| WARP 接口能力 | 当前生成策略 | 结论 |
| --- | --- | --- |
| IPv4-only | `UseIPv4` | 可强制 WARP IPv4 |
| IPv6-only | `UseIPv6` | 可强制 WARP IPv6 |
| IPv4/IPv6 双栈 | `UseIP` | 只有一个通用 `warp-out`，不能选择 WARP IPv4/IPv6 优先或回退 |

系统路由组合与 WARP 接口地址能力是两个独立维度，不能只看接口是否有双栈地址。

## 7. 已确认问题

### 7.1 P0：Xray-core v26.5.9+ 可能绕过当前 Happy Eyeballs

当前现代模板使用：

```text
Freedom settings.domainStrategy=AsIs
-> sockopt.domainStrategy=UseIP
-> sockopt.happyEyeballs
```

该结构在普通 Freedom 拨号链中成立。但 Xray-core `v26.5.9` 对 VLESS、VMess、Trojan、Hysteria、WireGuard 和 Shadowsocks 服务端入站引入了默认 Freedom 安全规则。只要存在该默认规则，Freedom 会先解析域名并把单个 IP 交给底层 dialer；`sockopt` 因而无法再看到域名和另一地址族。

该版本的实现还会优先查询 IPv4，只有没有 IPv4 结果时才查询 IPv6。因此在节点 A 上应用当前“IPv6 优先”现代模板，不能证明流量会先走 WARP IPv6。

结论：仅以“Xray 版本大于等于 `v25.6.8`”作为 Happy Eyeballs 可用条件不充分；必须同时处理 Freedom `finalRules` 的安全语义，并进行真实运行时验证。

### 7.2 P1：地址族被错误地当作出口身份

`IPv4-out` / `IPv6-out` 没有绑定“原生”或“WARP”。实际出口完全由 Linux 对该地址族的有效路由决定：

- 在节点 A，`IPv4-out` 是原生，`IPv6-out` 是 WARP。
- 在节点 B，`IPv4-out` 是 WARP，`IPv6-out` 是原生。
- 在 WARP 双栈全局模式，两个基础出站都会走 WARP。

菜单文案只显示地址族，用户无法在执行前确认实际出口身份。

### 7.3 P1：没有四个独立出口

当前不存在以下稳定、可单独引用的出站：

```text
native-ipv4-out
native-ipv6-out
warp-ipv4-out
warp-ipv6-out
```

因此双栈 VPS 安装 WARP 后，无法满足“四出口任意选择”的目标。

### 7.4 P1：外部 WARP 与项目网络层之间缺少稳定适配

菜单 `20` 把 WARP 安装和基础系统路由交给外部脚本，这个维护边界是正确的；问题不是 xray-agent 没有接管外部实现，而是外部操作完成后只做了部分探测，没有形成统一的网络快照、出口目录和项目自有策略路由生命周期。菜单 `6` 和菜单 `8` 因而仍无法稳定消费外部脚本产生的真实网络能力。

### 7.5 P2：双栈 WARP 只有一个 `UseIP` 出站

`warp-out` 和 `cn-out` 都只绑定 WARP 接口。WARP 双栈时，它们使用 `UseIP`，没有 WARP IPv4 优先、WARP IPv6 优先和 TCP 自动回退三个独立语义。

### 7.6 P2：geosite 输入会重复前缀

菜单提示用户输入 `geosite:openai`，但 `xray_agent_geosite_domains_json` 会对每个值再次添加 `geosite:`。实际生成结果为：

```json
["geosite:geosite:openai"]
```

输入契约和解析器契约不一致。

### 7.7 范围边界：旧安装兼容

旧安装升级和历史出站迁移不属于本次重构目标。本文只为全新安装的出口模型提供需求和回归基线。

## 8. 实施前支持结论

### 8.1 已支持

- 探测 IPv4/IPv6 有效默认接口。
- 探测 WARP 接口地址能力。
- 识别 WARP 接管 IPv4、IPv6或双栈默认路由。
- 在旧模型中强制选择 IPv4 或 IPv6。
- 把指定域名或 CN 规则绑定到一个 WARP 接口。
- 切换基础出站时保留 WARP/CN 等附加出站。

### 8.2 部分支持

- 节点 A、节点 B 这类“原生单栈 + WARP 补栈”可以通过地址族间接选择出口。
- 原生双栈 + WARP 专用接口可以实现原生默认、指定域名走通用 WARP。
- TCP 双栈域名具备设计上的 Happy Eyeballs 模板，但当前版本门槛和运行时安全链处理不完整。

### 8.3 未支持

- 原生 IPv4、原生 IPv6、WARP IPv4、WARP IPv6 四个出口独立选择。
- WARP 全局后从 Xray 明确绕回原生 IPv4/IPv6。
- 仅 Xray 全局走 WARP，同时系统其他进程保持原生。
- WARP 双栈内部的 IPv4/IPv6 优先和可靠 TCP 回退。
- UDP 地址族优先策略。
- 按用户、入站标签、协议、端口和任意 IP 的通用可视化分流。
- 旧安装升级和历史出站配置迁移。

## 9. 证据与验证范围

已完成：

- 仓库 Bash 语法检查。
- `tests/egress_catalog_test.sh` 和 `tests/egress_policy_test.sh` 的前置问题对照。
- `git diff --check`。
- 节点 A 的接口、默认路由、策略路由、WireGuard 状态、出口地址、Xray 版本和 Xray 出站只读检查。
- 节点 B 的服务器内部只读检查、四个绑定接口公网探测、旧 Xray 配置和 WARP 模式核对。
- 节点 A/B 的候选配置测试、事务备份、在线原子替换、服务恢复、网络状态不变检查和真实 TCP 探针。
- Xray-core `v26.5.9` 标签源码中 Freedom 默认安全规则和预解析行为核对。
- 当前 WARP 外部脚本所支持的全局/非全局和栈选项核对。

未完成：

- 原生双栈 + WARP 的第三台实机检查。
- 原生双栈节点的系统全局 WARP 模式切换和回滚演练。
- TCP/UDP、域名/IP 字面量的完整出口抓取验证。

## 10. 后续实现必须满足的验收基线

1. 每次选择都必须显示“地址族 + 出口提供者 + 接口/源地址”。
2. 不可用出口必须显示不可用原因，不得静默回退到系统默认。
3. 系统全局 WARP、Xray 默认出站和规则分流必须分别建模。
4. 节点 A、节点 B 和原生双栈节点必须使用同一套模型，不写按机器特判。
5. TCP Happy Eyeballs 必须在目标 Xray 版本上通过真实拨号验证。
6. UDP 必须单独选择地址族，不复用 TCP 自动回退文案。
7. WARP 全局模式必须验证公网入站源地址回程规则。
8. 全新安装不得依赖旧标签和旧模板，不长期保留双轨实现。
9. 所有生成配置必须在替换前通过 Xray 配置测试，失败时保持原配置不变。
10. 十五种系统组合和请求类型矩阵必须进入自动测试或可复现集成测试。

## 11. 上游依据

- [Xray Freedom 官方文档](https://xtls.github.io/config/outbounds/freedom.html)
- [Xray Sockopt 与 Happy Eyeballs 官方文档](https://xtls.github.io/config/transports/sockopt.html)
- [Xray 出站默认选择规则](https://xtls.github.io/config/outbound.html)
- [Xray 路由规则](https://xtls.github.io/config/routing.html)
- [Xray-core v26.5.9 Freedom 源码](https://github.com/XTLS/Xray-core/blob/v26.5.9/proxy/freedom/freedom.go)
- [Xray 基于 fwmark/sendThrough/interface 的分流说明](https://xtls.github.io/document/level-2/redirect.html)
- [当前外部 WARP 脚本](https://gitlab.com/fscarmen/warp/-/blob/main/menu.sh)

## 12. 实施结果

阶段 0-4 已在当前工作区完成：四个物理出口和三个自动出口已经分别建模，TCP/UDP 策略分离，策略文件成为唯一来源，旧模板和 routing profile 已删除。实现只面向全新安装，不包含旧配置迁移入口。

Happy Eyeballs 与私网安全链已经在 Xray-core `v25.6.8`、`v26.5.9` 和 `v26.7.28` 上通过真实 VLESS 入站测试。节点 A/B 已完成公网出口记录、候选配置测试、在线原子替换和不改 WireGuard/路由的验收；节点 B 还直接暴露并修复了“私网 IPv4 路由存在但原生公网 IPv4 不可用”的目录假阳性。尚未完成的是原生双栈 + WARP 第三台实机、系统 WARP 模式切换和完整 TCP/UDP/IP 字面量矩阵。
