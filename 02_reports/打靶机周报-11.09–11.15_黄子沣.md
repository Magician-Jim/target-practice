# 打靶机周报（2026.11.09--2026.11.15）

报告周期：2026.11.09--2026.11.15

| 项 | 内容 |
|---|---|
| 姓名 | 黄子沣 |
| 周期 | 2026.11.09–2026.11.15（2026-W46，周一至周日） |
| 本周靶机 | LAB / phpblog（Baby） |
| 过程台账 | `01_targets/2026-W45_LAB-phpblog/` |

## 【总体摘要】

- 遗留问题：共 5 个，已解决 4 个，有进展 1 个，无进展 0 个。
- 靶机结果：已在 2026-11-18 补完 root 提权并取得 flag；周报周期内实际停在 `momo`
  低权限阶段。
- 关键收获：确认“公开上传 → 页面模板路径穿越 → `momo` RCE”以及
  “低权限任务 → root 备份恢复 → 控制面文件写入”两条完整链路。
- 后续重点：保留 WP 与复现指导，完成第二遍脱稿复现和环境清理。

## 一、遗留问题跟踪

总：共 5 个问题，4 个已闭环，1 个待老师确认；root 提权已在后续补做中完成。

| 问题描述 | 结论 | 详细进展 / 结论说明 | 下周计划 | 状态 |
|---|---|---|---|---|
| VMware 与 VirtualBox 靶机网络不互通 | ✅ 已解决 | 两个虚拟机均迁入 VirtualBox，并接入同一 Host-only `192.168.56.0/24`；Kali 为 `.103`，phpblog 为 `.101` | 已关闭 | ✅ |
| WhatWeb/fuzz 目标变量与超时问题 | ✅ 已解决 | 先校验 `$TARGET`，再用 curl、WhatWeb、ffuf 分段验证；确认 Typecho 1.3.0 与 XML-RPC 路由 | 已关闭 | ✅ |
| 初始立足点未打通 | ✅ 已解决 | 审计上传与模板加载逻辑，利用页面模板路径穿越执行上传的 PHP，取得 `uid=1000(momo)` | 已关闭 | ✅ |
| root 提权尚未完成 | ✅ 已解决 | 读取 root 服务 token，利用可写 jobs/staging 恢复 `/root/.ssh/authorized_keys`，取得 root shell 与 flag | 已关闭 | ✅ |
| 离线源码审计是否计入独立完成 | ❓ 待老师确认 | 本轮通过关机镜像审计确认了后台会话、文件权限和 `blogbackup` 配置，成果可靠，但不再是纯黑盒路径 | 等待确认记录口径 | ❓ |

## 二、本周靶机进展

总：周报周期内完成到 `momo` 代码执行；后续补齐 root 提权与 flag 取证，攻击链已经闭环。

### 2.1 靶机信息

| 项 | 内容 |
|---|---|
| 平台 / 名称 | LAB / phpblog |
| 难度 | Baby |
| 目标系统 | Debian 13；Linux 6.12.73；PHP-FPM 8.4.24 |
| 开放端口 | `22/tcp` OpenSSH；`80/tcp` Apache/Typecho 1.3.0 |
| 实际耗时 | 未准确记录；多日分段，环境与源码审计占比较高 |

### 2.2 攻击链

| 阶段 | 做了什么 | 拿到什么 | 为什么有效 |
|---|---|---|---|
| 信息收集 | Host-only 探活、全端口扫描、Web 指纹与目录扫描 | 靶机 IP、22/80 端口、Typecho 1.3.0、上传与管理入口 | 攻击面收敛到 Web 应用及自定义模板 |
| 立足点 | 上传 PHP 到 `/tmp/submissions`，创建页面并将 `template` 指向该文件 | `momo` 用户命令执行 | Typecho 将主题目录与模板名拼接后直接 `require`，路径穿越可跳出主题目录 |
| 提权 | 读取 `blogbackup` token，写入 job/staging 并调用 `/restore` | root SSH 公钥被服务写入，随后获得 root shell | 服务以 root 运行，`momo` 可写任务目录，恢复目标包含 root SSH 公钥 |
| 结果 | 通过 Web 页面执行 `id` 并落盘证据 | `uid=1000(momo)` | Web 可见输出验证了 RCE，不依赖反向回连 |

### 2.3 关键根因

- **漏洞类型 / CWE**：路径穿越与文件包含，CWE-22 + CWE-98。
- **触发点**：`Widget/Contents/Page/Edit.php` 未过滤 `template`；`Widget/Archive.php` 将主题目录与模板名拼接后执行 `require`。上传页允许把任意文件写入 `/tmp/submissions`。
- **为什么存在**：模板名没有限制在主题目录内，PHP `open_basedir` 又允许访问 `/tmp`；文件上传缺少类型约束，PHP-FPM 用户 `momo` 可执行被包含文件。
- **修复方式**：模板名应与主题实际模板白名单匹配，并用 `realpath` 校验包含路径；上传文件应存于不可执行目录，限制类型并使用随机文件名；`open_basedir` 不应包含上传目录。
- **可迁移性**：凡是“后台选择模板/组件名 → 服务端拼接路径 → `include/require`”的 Web 管理面，都可能出现同类问题。
- **root 提权根因**：`blogbackup.service` 是 root 运行的 confused deputy；低权限组可以创建
  恢复任务，目标 allowlist 又包含 `/root/.ssh/authorized_keys`，使普通用户能够驱动 root
  覆盖身份认证文件。

### 2.4 与 IoT 方向的映射

- **固件中的同类形态**：路由器、摄像头 Web 管理后台常根据请求参数选择 `page`、`template`、`lang` 文件，再由 CGI/PHP 拼接路径包含；上传的升级包、皮肤包或日志目录也可能与 Web 根目录重叠。
- **高权限恢复面**：固件的配置导入、备份回滚和升级恢复常以 root 运行；若低权限 Web 用户能写任务或上传包，且目标包含启动脚本、SSH 密钥或计划任务，就会形成与 `blogbackup` 类似的 confused deputy。
- **对应 CVE**：本靶机的自定义模板链没有公开 CVE。公开漏洞侧核实了 [CVE-2024-35539](https://nvd.nist.gov/vuln/detail/CVE-2024-35539)（评论竞态）和 [CVE-2024-35540](https://nvd.nist.gov/vuln/detail/CVE-2024-35540)（存储型 XSS），二者与模板文件包含不是同一根因。
- **下一步验证点**：在固件解包后检索 `include`、`require`、`file_get_contents` 与模板参数，并梳理 Web 用户可驱动的 root 备份、恢复和升级服务。

### 2.5 耗时分布与卡点

| 阶段 | 计划 | 实际 | 偏差原因 |
|---|---|---|---|
| 信息收集 | 30 min | 多轮完成 | 前期跨虚拟化网络排障占用较多时间 |
| 立足点 | 65 min | 多轮排查 + 源码审计 | WhatWeb 超时、session 注入链不稳定，最终改用模板路径穿越 |
| 提权 | 60 min | 后续补做完成 | 在恢复会话与 `/tmp` 清理后重新建立低权限入口，再验证恢复链 |
| 写报告 | 40 min | 本次完成 | 浓缩过程，保留关键根因与证据 |

## 三、下周计划

总：phpblog 已完成；后续重点转为 WP 复现、第二遍脱稿训练和同类固件检查项沉淀。

| 类型 | 事项 | 计划完成时间 | 依赖 / 备注 |
|---|---|---|---|
| 跟进问题 | 按 WP 完成第二遍复现与清理 | 本周内 | 使用 [WP.md](WP.md) 和 [复现指导.md](复现指导.md) |
| 正常任务 | 完成 Basic Pentesting | 下周日 | 不依赖 phpblog 的遗留入口 |
| 新任务 | 补充“模板路径穿越 + 文件上传”固件检查卡片 | 下周四 | 关注 `open_basedir`、上传目录与包含路径 |

## 四、需要老师把关确认的问题

请直接回复序号：

1. 【待老师确认】本轮通过离线源码审计和助手接续完成，是否统一按“🟡 借助提示完成”记录？
   - 背景：低权限与 root 链路均已通过真实 HTTP、恢复接口和 SSH 复现，但数据库、服务代码和会话格式来自离线审计及助手整理。
   - 影响：确认口径后可准确更新台账和 WP。

---

## 五、后续完成记录（2026-11-18）

- 重新上传 `shell.php` 并恢复 `momo` 命令执行入口。
- 从 root 进程参数读取 `blogbackup` token，验证任务目录与恢复接口。
- 通过 `/restore` 写入 `/root/.ssh/authorized_keys`，取得 `uid=0(root)`。
- 读取 flag：`flag{root-7e934684eafe9fe6f1c32d6b06207c7f}`。
- 证据：`05_evidence/02_root_proof.txt`、`05_evidence/03_blogbackup_restore.txt`、
  `05_evidence/05_reproduction_root_proof.txt`、`05_evidence/06_reproduction_cleanup.txt`、
  `05_evidence/07_post_cleanup_verification.txt`。
- 完整技术说明：`WP.md`；逐步复现：`复现指导.md`。

---

> 交付方式：本文件是唯一源；`scripts/publish-report.ps1` 会导出到 `02_reports/打靶机周报-11.09–11.15_黄子沣.md`。
