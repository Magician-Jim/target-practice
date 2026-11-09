<#
.SYNOPSIS
    把某台靶机的 REPORT.md 导出到 02_reports，并按实验室命名规则改名。

.DESCRIPTION
    命名规则：打靶机周报-MM.DD至MM.DD_姓名.md
    源文件唯一：01_targets\<靶机>\REPORT.md

.EXAMPLE
    .\scripts\publish-report.ps1 -Target "2026-W45_THM-BasicPentesting"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [string]$Author = '黄子沣',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$reportPath = Join-Path $root (Join-Path '01_targets' (Join-Path $Target 'REPORT.md'))
if (-not (Test-Path $reportPath)) { throw "找不到周报源文件：$reportPath" }

$text = Get-Content -Path $reportPath -Raw -Encoding UTF8

$range = $null
# ① 新格式：报告周期：2026.11.02--2026.11.09
if ($text -match '报告周期[:：]\s*\d{4}\.(\d{2})\.(\d{2})\s*-{1,2}\s*\d{4}\.(\d{2})\.(\d{2})') {
    $range = '{0}.{1}–{2}.{3}' -f $Matches[1], $Matches[2], $Matches[3], $Matches[4]
}
# ② 旧格式：打靶机周报（11.02–11.09）
if (-not $range -and $text -match '([0-9]{2}\.[0-9]{2}–[0-9]{2}\.[0-9]{2})') { $range = $Matches[1] }
if (-not $range) { throw '无法从 REPORT.md 中解析出周期（形如 2026.11.02--2026.11.09 或 11.02–11.09），请检查报告抬头' }

$outName = '打靶机周报-{0}_{1}.md' -f $range, $Author
$outDir = Join-Path $root '02_reports'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir $outName

if ((Test-Path $outPath) -and (-not $Force)) {
    throw "已存在同名交付文件：$outPath`n确认要覆盖请加 -Force"
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($outPath, $text, $utf8)

if ($text -match '___' -or $text -match '\{\{') {
    Write-Warning '报告里还有未填的空（___ 或 {{占位符}}），确认是否已定稿再发。'
}

Write-Host ''
Write-Host "已导出：$outPath" -ForegroundColor Green
Write-Host ''
Write-Host '下一步：' -ForegroundColor Cyan
Write-Host '  1. 通读一遍，确认【总体摘要】能独立读懂'
Write-Host '  2. 需要 PDF 时：Word 打开另存为 PDF，或 pandoc 转换'
Write-Host '  3. 周一上午发给导师'
Write-Host ''
