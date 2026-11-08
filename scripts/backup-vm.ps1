<#
.SYNOPSIS
    备份一台 VMware Player 虚拟机（代替 Player 不支持的快照）。

.DESCRIPTION
    Workstation Player 没有快照功能（vmrun snapshot 会报"此操作不受支持"）。
    本脚本在虚拟机关机状态下，把整个虚拟机文件夹复制到 04_lab\images\_backup\<名字>_clean\。
    恢复时把备份拷回原目录即可。

.PARAMETER Name
    虚拟机目录名，例如 phpblog（对应 D:\Science\VM Workstation Player\phpblog\ 或同名 .vmx 所在目录）。

.PARAMETER Source
    虚拟机所在目录，默认 D:\Science\VM Workstation Player

.EXAMPLE
    .\scripts\backup-vm.ps1 -Name phpblog
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Source = 'D:\Science\VM Workstation Player',
    [string]$DestRoot,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $DestRoot) { $DestRoot = Join-Path $root '04_lab\images\_backup' }

if (-not (Test-Path $Source)) { throw "源目录不存在：$Source" }

# 找出这台虚拟机的所有文件（<Name>*，且排除已经叫 xxx_clean 的备份）
$files = Get-ChildItem -LiteralPath $Source -Filter "$Name*" -File -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -notlike '*_clean*' }
if (-not $files) { throw "在 $Source 里没找到以 '$Name' 开头的虚拟机文件，检查名字拼写" }

# 检查是否在运行 / 有锁
$locks = Get-ChildItem -LiteralPath $Source -Filter "$Name*.lck" -Force -ErrorAction SilentlyContinue
$running = Get-Process vmware-vmx -ErrorAction SilentlyContinue
if ($locks -or $running) {
    throw "虚拟机可能还在运行（发现 .lck 锁文件或 vmware-vmx 进程）。请先在 VMware 里【关机】，再备份。"
}

$dest = Join-Path $DestRoot "${Name}_clean"
if ((Test-Path $dest) -and $locks) { }
if (Test-Path $dest) {
    if (-not $Force) {
        throw "备份已存在：$dest`n要覆盖请加 -Force（会先删掉旧备份）"
    }
    Remove-Item -LiteralPath $dest -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null
$totalMB = 0
foreach ($f in $files) {
    Copy-Item -LiteralPath $f.FullName -Destination $dest
    $totalMB += $f.Length / 1MB
}

$note = @"
# 备份说明

- 虚拟机：$Name
- 备份时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- 来源：$Source
- 文件数：$($files.Count)，共 $([math]::Round($totalMB,1)) MB

## 恢复方法

1. 确认虚拟机已【关机】
2. 删除原目录下的 $Name* 文件
3. 把本目录下的所有文件拷回：$Source

## 注意

Workstation Player 不支持快照，本备份是等效替代。备份时虚拟机必须处于关机状态。
"@
[System.IO.File]::WriteAllText((Join-Path $dest '_RESTORE.txt'), $note, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "备份完成：$dest" -ForegroundColor Green
Write-Host ("文件 {0} 个，共 {1:N1} MB" -f $files.Count, $totalMB)
Write-Host ''
Write-Host '打崩了怎么恢复：' -ForegroundColor Cyan
Write-Host '  1. 关机'
Write-Host "  2. Remove-Item '$Source\$Name*' -Force"
Write-Host "  3. Copy-Item '$dest\*' '$Source\'"
Write-Host ''
