<p align="center">
  <a href="./README.md">English</a> | <strong>中文</strong>
</p>

<h1 align="center">Ambient Ops</h1>

<p align="center"><strong>把分散在局域网里的运行状态，汇总成一块安静、常亮、可自托管的信息屏</strong></p>
<p align="center">Codex TPS 汇总指标 · 路由器网络状态 · 浏览器与 Android 常驻屏</p>

<p align="center">
  <a href="https://github.com/gaofeng21cn/ambient-ops/releases/latest"><img src="https://img.shields.io/github/v/release/gaofeng21cn/ambient-ops" alt="最新版本"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="MIT 许可证"></a>
  <img src="https://img.shields.io/badge/deployment-Docker-blue.svg" alt="Docker 部署">
</p>

<table>
  <tr>
    <td width="33%" valign="top">
      <strong>主要用途</strong><br/>
      在可信局域网内统一查看 Codex 活跃度、网络吞吐、设备在线状态和宠物状态
    </td>
    <td width="33%" valign="top">
      <strong>使用入口</strong><br/>
      浏览器、五英寸 Android 常驻屏、Prometheus，以及可选的 Home Assistant
    </td>
    <td width="33%" valign="top">
      <strong>隐私边界</strong><br/>
      Codex 原始会话始终留在各台电脑；服务端只接收允许清单内的汇总指标
    </td>
  </tr>
</table>

> Ambient Ops 面向可信局域网，不是公网监控平台。显示页、状态接口和设备批准页默认没有浏览器登录；如需跨越不可信网络，必须增加 HTTPS、访问控制或私有 VPN。

## 给用户

### 这是什么

Ambient Ops 是一个自托管的局域网状态聚合器。它把多台电脑上的 Codex 使用情况、
兼容路由器的实时广域网计数器和设备在线状态，整理成一套适合常亮显示的界面。

它解决的不是“再做一个复杂监控平台”，而是下面这个更具体的问题：

- 想随手看到多台电脑上的 Codex 是否活跃、最近吞吐如何
- 想把网络下载、上传和延迟放在同一块常亮屏上
- 想让浏览器和专用 Android 屏幕读取同一个权威状态
- 想保留自托管和本地优先，不把会话内容交给第三方服务

### 与 Codex TPS 如何协同

[Codex TPS](https://github.com/gaofeng21cn/codex-tps) 运行在每台 macOS 或 Windows
电脑上，读取本机 Codex 已经写入的用量事件。它只向 Ambient Ops 发送机器名、平台、
采集时间、最近 `1 分钟 / 5 分钟` 的汇总 Token 计数、活跃会话数和可选宠物状态。

会话标识、本机路径、提示词、回复正文、工具调用内容和仓库文件都不会发送。

当前桌面版 Codex TPS 使用一次性设备批准流程：应用在本机生成独立设备密钥，
用户核对六位配对码后开始签名上报，不需要复制共享令牌。共享令牌只保留给旧版或
无界面的 Agent 部署。

### 工作方式

```text
各电脑上的 Codex TPS -- 经过认证的汇总快照 ----+
                                               |
SNMPv3 路由器 -------- 标准 IF-MIB 计数器 ------+--> Ambient Ops 容器
                                               |      |
/data ---------------- 状态与短期历史 ---------+      +--> 浏览器
                                                      +--> Android 常驻屏
                                                      +--> Prometheus
                                                      +--> Home Assistant（可选）
```

服务端、接口、SNMP 采集、局域网发现和前端都包含在同一个容器中。Android
常驻屏只负责发现服务和展示，不保存采集凭据，也不承担数据汇总逻辑。

### 你会得到什么

- 总览、网络、机器、单机负载、宠物和电子墨水屏六类显示页面
- 多台 Codex TPS 主机的聚合吞吐、活跃会话和新鲜度状态
- 基于标准 IF-MIB `Counter64` 的下载、上传和可选网络延迟
- Prometheus 文本指标和可选 Home Assistant 同步
- 通过局域网自动发现服务器的 Android 常驻屏
- 版本化 Docker 镜像、健康检查、持久化数据和可回滚升级路径

### 快速开始

需要 Docker Engine、Docker Compose v2、`curl` 和 `openssl`。

```bash
git clone https://github.com/gaofeng21cn/ambient-ops.git
cd ambient-ops
./scripts/ambient-ops.sh init
```

这会生成最小的 `codex-only` 配置。普通用户只需编辑 `.env` 中的站点名称和时区：

```dotenv
SITE_NAME=Home Ambient Ops
DISPLAY_TIME_ZONE=Asia/Shanghai
```

模板默认固定到经过审查的发布镜像；如需升级，才把 `AMBIENT_OPS_IMAGE` 改为
[最新发布版本](https://github.com/gaofeng21cn/ambient-ops/releases/latest)对应的版本化标签，
不要使用 `latest`。

如果一开始就需要路由器遥测，请在初始化时选择配置模式：

```bash
./scripts/ambient-ops.sh init --profile snmpv3
# 或者：./scripts/ambient-ops.sh init --profile unifi-api
```

SNMPv3 模式还需要通过交互式命令写入两份密码：

```bash
./scripts/ambient-ops.sh set-secret unifi_snmp_auth_password
./scripts/ambient-ops.sh set-secret unifi_snmp_priv_password
./scripts/ambient-ops.sh validate
./scripts/ambient-ops.sh up
./scripts/ambient-ops.sh status
```

`init` 不会覆盖已有配置。它生成稳定的实例 ID 和 Agent 共享令牌，但不会把敏感值
打印到终端。密码与令牌保存在已忽略的 `secrets/` 目录，不应写进 `.env`、命令行、
日志、截图或 Git。

完整步骤见[中文安装教程](docs/installation.zh-CN.md)。群晖部署、升级、回滚和
Android 常驻屏安装也以该文档及 `docs/` 下的专项说明为准。

### 三种网络模式

| 模式 | 适用场景 | 额外配置 |
| --- | --- | --- |
| `codex-only` | 只显示 Codex 和宠物状态 | `init` 默认生成；不需要路由器配置 |
| `snmpv3` | 首选的通用路由器采集路径 | `init --profile snmpv3`；路由器地址、只读用户、接口选择器和两份密码 |
| `unifi-api` | UniFi Network API 备用路径 | `init --profile unifi-api`；控制器地址、站点和 API Key 文件 |

SNMP 路径使用标准 IF-MIB，不依赖 UniFi 私有 MIB。设备仍需支持 SNMPv3
`authPriv`，并能为真实广域网接口提供 `ifHCInOctets` 与 `ifHCOutOctets`。
“已开启 SNMP”不等于已经兼容，必须按 [`docs/unifi.md`](docs/unifi.md) 做实机验证。

### 重要边界

- 一个站点只应运行一个对外广播并接收上报的 Ambient Ops 实例。
- 生产环境的 `compose.yaml` 已经是完整的 host-network 定义，DSM
  Container Manager 可以单独读取；`compose.host-network.yaml` 仅为旧的命令行流程保留，
  `compose.local-build.yaml` 仅用于本地开发。
- 不要把服务端口直接暴露到互联网。显示页和设备批准页默认信任所在局域网。
- 升级时保留 `.env`、`INSTANCE_ID`、`secrets/` 和 `ambient_ops_data` 数据卷。
- 不要执行 `docker compose down -v`，除非你明确要永久删除持久数据。

## 面向 Agent

### 推荐任务表达

可以直接把下面的任务交给 Codex 或其他本机 Agent，并只替换非敏感字段：

```text
在 <Docker 主机> 的 <绝对目标目录> 安装或升级 Ambient Ops。
使用 SITE_NAME=<站点名称>、DISPLAY_TIME_ZONE=<IANA 时区>、
AMBIENT_OPS_NETWORK_MODE=<codex-only|snmpv3|unifi-api>。

严格遵循 docs/installation.zh-CN.md、docs/agent-installation.zh-CN.md 和
scripts/ambient-ops.sh。生产环境只使用经过审查的版本化 GHCR 镜像，不在 NAS
上构建源码，不使用移动标签，不创建不必要的 GitHub 登录或计划任务。

不要索取、读取、打印或复制令牌与密码。需要写入 secret 时，只让我在可信终端
执行文档中的交互式 set-secret 命令。已有安装必须保留 .env、INSTANCE_ID、
secrets/ 和 ambient_ops_data，禁止执行 docker compose down -v。

完成前必须回读 Compose 最终镜像、/healthz、/api/status、mDNS 发现、预期机器
列表和 Android 常驻屏连接状态；不能把构建成功、HTTP 200 或容器正在运行当成
完整验收。
```

### Agent 安装顺序

全新安装：

```bash
git clone https://github.com/gaofeng21cn/ambient-ops.git <target>
cd <target>
git rev-parse HEAD
./scripts/ambient-ops.sh init --profile <codex-only|snmpv3|unifi-api>
```

随后只修改允许公开的 `.env` 字段；真实令牌和密码由用户在可信终端写入。

```bash
./scripts/ambient-ops.sh validate
docker compose --env-file .env -p ambient-ops \
  -f compose.yaml -f compose.host-network.yaml config --images
./scripts/ambient-ops.sh up
./scripts/ambient-ops.sh status
```

已有安装不得重新运行 `init`。升级前先记录当前仓库提交、实际镜像、健康状态和
准确回滚命令，再把 `AMBIENT_OPS_IMAGE` 改为经过审查的新版本，重新执行验证与
验收。

### Agent 权限与证据边界

- 可以检查 secret 文件是否存在、属主和权限；不得打开内容或把哈希写进公开报告。
- 可以配置路由器地址、只读用户名和接口选择器；不得要求用户把密码粘贴进对话。
- 可以运行健康检查；必须区分“进程存活”和“已配置数据源可用”。
- 可以安装 Android 常驻屏；批准、设备签名和真实重启仍需用户明确参与。
- 必须保持单实例规则，迁移时先停止旧实例写入，再启动新的局域网权威实例。

完整合同见[中文 Agent 安装指南](docs/agent-installation.zh-CN.md)。

## 文档

- [中文安装教程](docs/installation.zh-CN.md)
- [中文 Agent 安装指南](docs/agent-installation.zh-CN.md)
- [安全与隐私边界](docs/security.md)
- [Agent 上报接口](docs/agent-push-api.md)
- [路由器与 SNMPv3](docs/unifi.md)
- [群晖部署](docs/deployment-synology.md)
- [Android 常驻屏](docs/macos-htc-kiosk.md)
- [迁移验收清单](docs/production-migration-checklist.md)

## 技术验证

```bash
npm ci
npm test
npm run build
docker compose -f compose.yaml config
docker compose -f compose.yaml -f compose.host-network.yaml config
python3 ops/public-readiness-check.py
```

项目采用 [MIT License](LICENSE)。
