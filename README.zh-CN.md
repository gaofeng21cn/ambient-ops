# Ambient Ops

[English](README.md) | **简体中文**

Ambient Ops 是一个面向可信局域网的自托管状态聚合器和五英寸动态信息屏。
每台 Mac 或 Windows 电脑上的 Codex TPS 只上传汇总用量；Ambient Ops 还可
通过只读 SNMPv3 采集兼容路由器的实时 WAN 计数器，并把统一状态提供给浏览器、
Home Assistant 和专用 Android Kiosk。

屏幕端不保存采集凭据，也不承担业务逻辑。Android 客户端通过局域网 mDNS
发现唯一的 Ambient Ops 实例，正常运行不需要 USB 或 `adb reverse`。

当前产品定位是“有引导的 Docker 自部署”，不是完全零配置。普通安装只填写一份
`.env`，敏感值单独放在 `secrets/`。路由器指标是可选项：只需要 Codex 与宠物
状态时可使用 `codex-only` 模式。

正式版 `v0.1.12` 已提供：

- 公开的 `linux/amd64` 与 `linux/arm64` 镜像
  `ghcr.io/gaofeng21cn/ambient-ops:0.1.12`
- macOS 与 Windows 桌面版一次性设备配对，不复制共享 agent token
- 由项目固定证书签名的 `Ambient-Ops-Kiosk-1.2.7.apk` 及 SHA-256 校验文件
- NAS 匿名拉取镜像；正常部署不需要 GitHub Token，也不在 NAS 上构建源码

同一个版本化 Docker 镜像内置了 GitHub Release 中完全相同的签名 APK。首次安装
后，已 root 的 Kiosk 可以从当前选中的局域网服务器获取后续版本，不再依赖 USB；
它只接受固定包名、固定项目证书、递增 `versionCode` 和 SHA-256 完全匹配的 APK。

Kiosk `1.2.7` 还会读取当前服务器由前端构建内容生成的 UI revision。Docker
替换导致页面内容变化后，客户端连续两次确认新 revision，再执行一次 WebView
刷新；查询失败时保留当前画面。因此后续更新 Docker 即可让所有在线 Kiosk
自行刷新，不需要 USB，也不会固定周期盲目重载。

## 架构

```text
各电脑 Codex TPS -- 带认证的汇总快照 --------+
                                              |
SNMPv3 路由器 -- IF-MIB Counter64 轮询 -------+--> Ambient Ops 容器
                                              |      |
/data -------- 机器状态与短期网络历史 ---------+      +--> Android Kiosk
                                                     +--> 浏览器
                                                     +--> Home Assistant（可选）
```

Codex 原始 session 文件始终留在各自电脑。服务端、API、SNMP 采集、mDNS
广播和 React 前端位于同一个容器，Android Kiosk 是独立客户端。

## 生产环境快速开始

需要 Docker Engine、Docker Compose v2、`curl` 和 `openssl`。

```bash
git clone https://github.com/gaofeng21cn/ambient-ops.git
cd ambient-ops
./scripts/ambient-ops.sh init
# 编辑 .env；若启用 SNMPv3，再录入下方两份密码。
./scripts/ambient-ops.sh validate
./scripts/ambient-ops.sh up
```

`init` 不会覆盖已有配置。它会生成稳定的实例 ID 和 agent token，但不会把
任何敏感值打印到终端。启用 SNMPv3 时，用交互式命令写入密码，避免进入 shell
历史：

```bash
./scripts/ambient-ops.sh set-secret unifi_snmp_auth_password
./scripts/ambient-ops.sh set-secret unifi_snmp_priv_password
```

Linux 与群晖上容器以 UID/GID 1000 运行。密码全部写完后按脚本提示执行一次
`sudo chown -R 1000:1000 secrets`，不要用 `chmod 644` 绕过权限。

完整普通用户流程见[中文安装教程](docs/installation.zh-CN.md)。需要 Agent
代为安装时，使用[中文 Agent 安装指南](docs/agent-installation.zh-CN.md)；指南
明确了凭据、持久卷、升级和回滚边界。英文对应文档是
[Installation guide](docs/installation.md) 与
[Agent installation guide](docs/agent-installation.md)。

## 三种网络配置

| `.env` 中的模式 | 适用情况 | 还需要填写 |
| --- | --- | --- |
| `AMBIENT_OPS_NETWORK_MODE=codex-only` | 只显示 Codex 与宠物状态 | 无路由器配置 |
| `AMBIENT_OPS_NETWORK_MODE=snmpv3` | 标准 SNMPv3 路径 | 地址、用户、WAN 接口、两份密码 |
| `AMBIENT_OPS_NETWORK_MODE=unifi-api` | UniFi API 备用路径 | URL、API key 文件 |

SNMP 采集基于标准 IF-MIB，而不是 UniFi 私有 MIB，因此并不绑定 UniFi 品牌。
但设备必须提供 SNMPv3 `authPriv`、`ifHCInOctets`、`ifHCOutOctets`，并且硬件
流量卸载不能绕开这些计数器。OpenWrt 等设备需要按实机验证，不能仅凭“已启用
SNMP”就认定兼容。完整边界和验证方法见 [`docs/unifi.md`](docs/unifi.md)。

## 安装 Android Kiosk

从 [Ambient Ops v0.1.12 Release][ambient-ops-v0.1.12]
下载 APK 和同名 `.sha256`：

```bash
shasum -a 256 -c Ambient-Ops-Kiosk-1.2.7.apk.sha256
adb install -r Ambient-Ops-Kiosk-1.2.7.apk
adb shell cmd package set-home-activity \
  cn.gaofeng.ambientops.kiosk/.MainActivity
```

不要先卸载生产版，否则会清除已记住的实例；不要使用不同签名证书的 APK 覆盖。
`1.2.1` 及后续版本安装完成后，Kiosk 会在页面健康后检查当前 Ambient Ops 的更新接口，
随后每 6 小时检查一次；只在接入外部电源且 Wi-Fi 在线时下载。无人值守安装需要 Magisk
root，并首次永久允许 Kiosk 的 `su` 请求。没有 root 时仍可手工校验 Release 后
执行 `adb install -r`。日常运行和自动更新都不需要 USB 或 GitHub 凭据。

`1.2.7` 在页面可见时每 15 秒检查一次 `/api/v1/ui/revision`。首次响应只建立
基线；revision 变化并连续确认两次后只刷新一次。断网或异常响应不会覆盖当前
页面。

## 验收

```bash
./scripts/ambient-ops.sh status
curl -fsS http://<server-ip>:8787/api/status
```

至少确认：

- 容器使用版本化 GHCR 镜像，Compose 中没有 `build:`。
- `/healthz` 的 `mode` 为 `live`。
- 各 Codex TPS 主机出现且状态为 `live`。
- 使用 SNMPv3 时 `network=live`；`codex-only` 模式下网络状态不作为验收项。
- HTC 在无 USB、无 `adb reverse` 的情况下通过 Wi-Fi 恢复四页显示。
- NAS 或 Docker 主机重启后容器依靠 `restart: unless-stopped` 自动恢复。

## 文档入口

- [中文安装教程](docs/installation.zh-CN.md)：普通用户安装、升级与回滚
- [中文 Agent 指南](docs/agent-installation.zh-CN.md)：Agent 安装提示词与边界
- [`docs/deployment-synology.md`](docs/deployment-synology.md)：群晖高级部署与迁移细节
- [`docs/security.md`](docs/security.md)：安全边界
- [`docs/agent-push-api.md`](docs/agent-push-api.md)：Agent push 协议
- [`docs/home-assistant.md`](docs/home-assistant.md)：Home Assistant 集成
- [`android-kiosk/README.md`](android-kiosk/README.md)：Android 构建、签名和升级

## 开发

```bash
npm ci
npm test
npm run build
```

本地 demo 才使用 `compose.local-build.yaml`。生产环境只拉取公开的版本化镜像，
不得把本地构建 override 加进群晖项目。

## 许可证

MIT

[ambient-ops-v0.1.12]: https://github.com/gaofeng21cn/ambient-ops/releases/tag/v0.1.12
