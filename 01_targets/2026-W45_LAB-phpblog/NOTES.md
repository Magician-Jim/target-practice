# 2026-W45_LAB-phpblog 作战笔记

> 机器：LAB / phpblog（Baby）
>
> 最终结果：root，已取 flag
>
> 完整技术说明：[WP.md](WP.md)
>
> 复现步骤：[复现指导.md](复现指导.md)
>
> 个人思考与技术复盘：[技术复盘报告.md](技术复盘报告.md)

## 时间线

| 阶段 | 动作 | 结果 |
|---|---|---|
| 环境 | VirtualBox Host-only，Kali `.103`，phpblog `.101` | 网络连通 |
| 侦察 | `nmap`、首页指纹、Typecho 主题入口 | 22/80，Typecho 1.3.0 |
| 审计 | 读取镜像中的数据库、FPM pool、主题与服务配置 | 定位模板包含与 `blogbackup` |
| 立足 | 上传 PHP 到 `/tmp/submissions`，页面模板路径穿越 | `momo` RCE |
| 提权 | 读取 token，写入 job/staging，调用 `/restore` | root SSH |
| 取证 | `id`、flag、服务日志、源码与配置 | 证据已保存 |
| 复现收尾 | 用户独立按指导完成第二次复现 | root 和 flag 再次验证 |
| 清理 | 恢复原始 root 公钥并删除测试任务、staging 与 shell | 攻击入口失效 |

## 有效入口

```bash
# 上传
curl -F 'draft=@phpblog_shell.php;filename=shell.php' \
  http://192.168.56.101/usr/themes/classic-22/submit/

# 模板页面
curl 'http://192.168.56.101/index.php/audit-template.html?cmd=id'
```

页面模板值：

```text
../../../../../../tmp/submissions/shell.php
```

## 关键判断

1. 上传目录不在 Web 根目录，不代表不能被 PHP 执行；关键是 `open_basedir` 和 `require_once`。
2. 页面模板名来自数据库字段，但最终进入文件系统路径拼接，属于不可信数据进入 sink。
3. `blogbackup` 的 allowlist 包含 `/root/.ssh/authorized_keys`，使高权限恢复服务变成了
   root 持久化接口。
4. token 出现在 root 进程的 argv 中，普通用户可通过 `ps` 读取；认证边界实际失效。
5. 遇到问题时应先建立“输入 → 数据存储 → 执行 sink → 权限结果”的链路，而不是只盯单个 CVE。

## 卡点与修正

### `/tmp` 在重启后为空

第一轮留下 `audit-template` 页面，但 `/tmp/submissions/shell.php` 随系统重启消失。
页面仍在，但访问时只渲染普通页面。重新提交同名 `shell.php` 后立即恢复执行。

### 管理员密码不是明显弱口令

直接尝试常见组合没有成功。后续利用数据库中的 `authCode` 和 Typecho Cookie 算法恢复后台
会话，避免把时间浪费在 phpass 爆破上。

### 早期 session 链不稳定

`upload_progress` 与 `TempCleaner` 的序列化链在本地 PHP 复现中成立，但目标侧没有稳定证明
命令执行。最终没有把它当作主链，而是选择上传 + 模板包含这一条可重复验证的路径。

## 证据索引

- `05_evidence/lowpriv_rce.txt`
- `05_evidence/02_root_proof.txt`
- `05_evidence/03_blogbackup_restore.txt`
- `05_evidence/05_reproduction_root_proof.txt`
- `05_evidence/06_reproduction_cleanup.txt`
- `05_evidence/07_post_cleanup_verification.txt`
- `03_privesc/agent.py`
- `03_privesc/blogbackup.service`
- `03_privesc/php-fpm-blog.conf`

## 下次同类机器的检查顺序

1. 先看高权限服务和组可写目录。
2. 再看 Web 输入是否能驱动这些目录或服务。
3. 最后才考虑内核漏洞和复杂对象注入。
4. 每拿到一个权限点，立刻记录并能用最小命令复现。
