---
week: 2026-W45
platform: LAB
name: phpblog
difficulty: Baby
date_range: 11.09–11.15
ip: 192.168.56.101
os: Linux
result: 🟡 已获 momo RCE，待 root
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

> 已通过页面模板路径穿越取得 `momo` 低权限 RCE；root 提权链已定位但尚未执行，环境与源码审计是主要时间成本。

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
| 提权 | 🔄 未完成 | 已定位 blogbackup root 恢复链 |
| 取证 | 🔄 部分完成 | 已保存 `05_evidence/lowpriv_rce.txt`，root flag 未取得 |

## 复盘（打完后填）

- 走错的方向：长期尝试不稳定的 session 注入并反复更换回调 payload。
- 真正省时间的一步：源码审计确认上传、模板和文件权限后，直接构造页面模板路径穿越。
- 下次同类机器我会先做什么：先完成足迹与权限模型，再审计模板、上传、备份等拼接路径。
