<#
.SYNOPSIS
    为本周靶机创建标准工作目录（含模板、子目录、台账行）。

.DESCRIPTION
    自动计算 ISO 周次与周一至周日区间，目录命名形如 2026-W45_THM-BasicPentesting。

.EXAMPLE
    .\scripts\new-target.ps1 -Platform THM -Name "Kenobi" -Difficulty Easy

.EXAMPLE
    .\scripts\new-target.ps1 -Platform HTB -Name "Meow" -Difficulty Easy -Date 2026-11-16
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Platform,
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Difficulty = 'Easy',
    [datetime]$Date = (Get-Date),
    [string]$Author = '黄子沣',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Get-IsoWeekInfo {
    param([datetime]$Day)
    $dow = [int]$Day.DayOfWeek          # Sunday = 0
    if ($dow -eq 0) { $dow = 7 }        # ISO: Monday = 1 ... Sunday = 7
    $thursday = $Day.Date.AddDays(4 - $dow)
    $isoYear = $thursday.Year
    $jan1 = [datetime]::new($isoYear, 1, 1)
    $isoWeek = [int][math]::Floor((($thursday - $jan1).Days) / 7) + 1
    return [pscustomobject]@{
        Year    = $isoYear
        Week    = $isoWeek
        Monday  = $Day.Date.AddDays(- ($dow - 1))
        Sunday  = $Day.Date.AddDays(7 - $dow)
    }
}

$iso = Get-IsoWeekInfo -Day $Date
$weekTag = '{0}-W{1:00}' -f $iso.Year, $iso.Week
$dateRange = '{0}.{1:00}–{2}.{3:00}' -f $iso.Monday.Month, $iso.Monday.Day, $iso.Sunday.Month, $iso.Sunday.Day

$safeName = ($Name -replace '\s+', '') -replace '[\\/:*?"<>|]', '-'
$folder = '{0}_{1}-{2}' -f $weekTag, $Platform, $safeName
$targetDir = Join-Path $root (Join-Path '01_targets' $folder)

if ((Test-Path $targetDir) -and (-not $Force)) {
    throw "目录已存在：$targetDir`n如需重建请加 -Force（会覆盖模板文件）"
}

foreach ($sub in @('01_recon', '02_exploit', '03_privesc', '04_loot', '05_evidence')) {
    $p = Join-Path $targetDir $sub
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    $keep = Join-Path $p '.gitkeep'
    if (-not (Test-Path $keep)) { New-Item -ItemType File -Path $keep | Out-Null }
}

$map = @{
    WEEK        = $weekTag
    DATE_RANGE  = $dateRange
    TARGET      = $folder
    PLATFORM    = $Platform
    NAME        = $Name
    DIFFICULTY  = $Difficulty
    DATE        = $Date.ToString('yyyy-MM-dd')
    AUTHOR      = $Author
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$tplDir = Join-Path $root '00_meta\templates'
foreach ($tpl in @('META.md', 'NOTES.md', 'REPORT.md', 'WP.md')) {
    $src = Join-Path $tplDir $tpl
    if (-not (Test-Path $src)) { Write-Warning "模板缺失：$src"; continue }
    $text = Get-Content -Path $src -Raw -Encoding UTF8
    foreach ($k in $map.Keys) { $text = $text.Replace('{{' + $k + '}}', [string]$map[$k]) }
    [System.IO.File]::WriteAllText((Join-Path $targetDir $tpl), $text, $utf8)
}

# ---- 追加台账行 ----
$indexPath = Join-Path $root 'INDEX.md'
if (Test-Path $indexPath) {
    $lines = New-Object System.Collections.Generic.List[string]
    Get-Content -Path $indexPath -Encoding UTF8 | ForEach-Object { $lines.Add($_) }

    $headerIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('| 周次')) { $headerIdx = $i; break }
    }
    if ($headerIdx -ge 0) {
        $insertAt = $headerIdx + 2
        while ($insertAt -lt $lines.Count -and $lines[$insertAt].StartsWith('|')) { $insertAt++ }
        $row = '| W{0:00} | {1} | {2} | {3} | {4} | 🔄 进行中 | — | — |' -f $iso.Week, $dateRange, $Name, $Platform, $Difficulty
        if (-not ($lines -contains $row)) { $lines.Insert($insertAt, $row) }
        [System.IO.File]::WriteAllLines($indexPath, $lines, $utf8)
    }
    else {
        Write-Warning 'INDEX.md 里没找到「| 周次 |」表头，台账未更新'
    }
}

Write-Host ''
Write-Host "已创建：$targetDir" -ForegroundColor Green
Write-Host "周次  ：$weekTag（$dateRange）"
Write-Host ''
Write-Host '下一步：' -ForegroundColor Cyan
Write-Host "  1. 打开 $folder\META.md，填训练目标与止损点"
Write-Host '  2. 开工前给靶机打快照，然后开始计时'
Write-Host '  3. 命令输出直接重定向进 01_recon\，别复制粘贴到笔记里'
Write-Host ''
