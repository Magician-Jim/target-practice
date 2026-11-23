---
week: 2026-W45
platform: LAB
name: phpblog
difficulty: Baby
date_range: 11.09–11.15
ip: 192.168.56.101
os: Linux
result: 🟡 借助源码审计与助手指导完成 root，已取旗
time_spent: 未准确计时
cwe: [CWE-22, CWE-98]
---

# 2026-W45_LAB-phpblog

## 靶机档案

| 项 | 值 |
|---|---|
| 靶机名 | phpblog |
| 作者 | momo |
| 靶机 ID | 818 |
| 系统 | Linux |
| 难度 | Baby |
| 测试 | MJ |
| 来源 | 师兄分享（QQ 文件，OVA 本地导入） |
| 分发链接 | https://qfile.qq.com/q/VijcKsIxAA |

## 一句话结论

> 通过匿名上传与页面模板路径穿越取得 `momo` RCE，再利用 root 级 `blogbackup`
> 恢复服务写入 root SSH 公钥并取得 flag；完整攻击链和复现指导已归档。

## 训练目标（开工前填，5 分钟）

- 这台机器的定位：**第一台**。目标不是"打得多漂亮"，是**把整套流程走通一遍，并证明自己能记录**。
- 要练的具体能力：☑ 信息收集 ☑ Web 入口 ☑ 提权 ☑ 报告写作（四个全勾，因为这是第一台）
- 我最想验证的一件事：
- 它哪一部分能映射到 IoT 固件：
  > 提示：博客类 web 应用 ≈ 路由器/摄像头管理后台。默认口令、上传点、参数注入，这三类在固件里占了大半。
- 3 小时打不完时，我的止损点是：

## 环境

| 项 | 内容 |
|---|---|
| 攻击机 | Kali 2026.x，VirtualBox Host-only |
| 靶机 | phpblog，VirtualBox Host-only `192.168.56.101` |
| 备份 | VirtualBox 快照 `before-source-audit`；仍保留 VMware 及 OVA 基线 |
| 开始时间 | 2026-11-10，多日分段 |

## 结果

| 阶段 | 结果 | 备注 |
|---|---|---|
| 信息收集 | ✅ 完成 | 22/80；Typecho 1.3.0；Apache 2.4.68；PHP 8.4.24 |
| 立足点 | ✅ 完成 | 页面模板路径穿越执行上传 PHP，获得 `momo` RCE |
| 提权 | ✅ 完成 | 利用 `blogbackup` 任务恢复 `/root/.ssh/authorized_keys` |
| 取证 | ✅ 完成 | 已保存低权限 RCE、root 身份、flag 和恢复日志 |

## 复盘（打完后填）

- 走错的方向：长期尝试不稳定的 session 注入并反复更换回调 payload。
- 真正省时间的一步：先建立“上传落点、模板拼接、root 服务、可写目录”之间的权限图。
- 下次同类机器我会先做什么：先枚举高权限服务与组可写目录，再检查 Web 输入能否驱动它们。
