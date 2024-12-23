# 目录

# 1.N合一共存脚本
## 特性
- 只支持[Xray-core[XTLS]](https://github.com/XTLS/Xray-core)
- 支持VLESS[VLESS TLS/REALITY VISION]
- 支持VLESS[VLESS TLS/REALITY XHTTP]
- 兼容 VLESS/VMess/trojan 协议
- 支持Debian、Ubuntu、Centos系统，支持主流的cpu架构。
- 支持任意组合安装、支持多用户管理、支持添加多端口、
- 支持卸载后保留tls证书
- 支持WARP分流、IPv6分流
- 支持日志管理、域名黑名单管理、核心管理、伪装站点管理
- **支持Reality和XHTTP一键安装**
- **支持将CNIP分流至WARP或者直接阻止**
- **TLS证书申请方式：支持ACME以API的方式申请泛域名证书、DNS申请、80端口申请**

## 支持的安装类型
- VLESS+Reality+xtls-rprx-vision【**⭐推荐⭐**】
- VLESS+Reality+XHTTP【支持0-rtt、支持CDN、延迟低】【**⭐推荐⭐**】
- VLESS+TCP+xtls-rprx-vision【**推荐**】
- VLESS+TLS+XHTTP【支持0-rtt、支持CDN、延迟低】【**推荐**】
- VLESS+WS+TLS【支持CDN】
- Trojan+TCP+TLS
- VMess+WS+TLS【支持CDN】

## 注意事项

- **修改Cloudflare->SSL/TLS->Overview->Full**
- **使用纯净系统安装，如使用其他脚本安装过并且自己无法修改错误，请重新安装系统后再次尝试安装**
- 不支持非root账户
- **如发现Nginx相关问题，请卸载掉自编译的nginx或者重新安装系统**
- **不推荐GCP用户使用**
- **不推荐使用Centos以及低版本的系统，如果Centos安装失败，请切换至Debian10重新尝试，脚本不再支持Centos6、Ubuntu 16.x**
- **Oracle Cloud有一个额外的防火墙，需要手动设置**
- **Oracle Cloud仅支持Ubuntu**
- **如果使用gRPC通过cloudflare转发,需要在cloudflare设置允许gRPC，路径：cloudflare Network->gRPC**
- **gRPC目前处于测试阶段，可能对你使用的客户端不兼容，如不能使用请忽略**

## 安装脚本

- 支持快捷方式启动，安装完毕后，shell输入【**vasma**】即可打开脚本，脚本执行路径[**/etc/xray-agent/install.sh**]

- Latest Version【推荐】

```
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/suysker/xray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```


# 许可证

[AGPL-3.0](https://github.com/suysker/xray-agent/blob/master/LICENSE)

## Stargazers over time

[![Stargazers over time](https://starchart.cc/mack-a/v2ray-agent.svg)](https://starchart.cc/mack-a/v2ray-agent)
