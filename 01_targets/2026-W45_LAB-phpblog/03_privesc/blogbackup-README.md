# blogbackup

站点备份/恢复代理。systemd 管理，只监听回环地址 `127.0.0.1:9001`。

## 启动

`blogbackup.service` 调用 `start.sh`，由 systemd 传入：

```
--token <每次启动随机生成> --listen 127.0.0.1:9001
```

## 接口

所有接口都要带 token：查询参数 `?token=<token>` 或请求头 `X-Token: <token>`。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/status` | 服务状态和任务名列表 |
| GET | `/jobs` | 读取 `/var/lib/blogbackup/jobs/*.json` |
| POST | `/restore` | 执行恢复，body `{"id":"<任务名>"}` |

## 任务文件

`/var/lib/blogbackup/jobs/` 由站点用户维护，示例：

```json
{
  "id": "daily-www",
  "source": "/var/lib/blogbackup/staging/www-index.php.bak",
  "dest": "/var/backups/blog/www-index.php.bak",
  "schedule": "daily"
}
```

恢复源必须是 `/var/lib/blogbackup/staging/` 下的普通文件（realpath 校验，拒绝软链）。
`dest` 只允许以下三个恢复目标，复制后统一为 `root:root`，不保留源文件权限：

- `/var/backups/blog/www-index.php.bak`（644）
- `/etc/cron.d/blogbackup`（644）
- `/root/.ssh/authorized_keys`（600）
