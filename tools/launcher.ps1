# Clouds-remain 发布中心
# 常驻菜单启动器：调用 publish.ps1 完成具体操作，操作结束后返回本菜单。

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Core = Join-Path $PSScriptRoot 'publish.ps1'
$script:Icon = Join-Path $PSScriptRoot 'publisher-v3.ico'
$script:Version = '1.2.0'
$script:PowerShell = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
if (-not $script:PowerShell) { $script:PowerShell = Join-Path $PSHOME 'powershell.exe' }

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $Host.UI.RawUI.WindowTitle = 'Clouds-remain 发布中心'
} catch { }

function Get-ChangeCount {
    try {
        $lines = @(& git -C $script:RepoRoot -c core.quotepath=false status --porcelain -- source/_posts 2>$null)
        return @($lines | Where-Object { $_ -match '\.md$' -and $_ -notmatch '\.obsidian' }).Count
    } catch {
        return 0
    }
}

function Get-Branch {
    try { return (& git -C $script:RepoRoot branch --show-current 2>$null).Trim() } catch { return 'unknown' }
}

function Show-Banner {
    $branch = Get-Branch
    $changes = Get-ChangeCount
    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════════════════╗' -ForegroundColor DarkCyan
    Write-Host '  ║          C L O U D S - R E M A I N                   ║' -ForegroundColor Cyan
    Write-Host ("  ║          博客发布中心  v{0,-8}                    ║" -f $script:Version) -ForegroundColor Cyan
    Write-Host '  ╚══════════════════════════════════════════════════════╝' -ForegroundColor DarkCyan
    Write-Host ("   分支: {0}    待发布文章: {1}    时间: {2}" -f $branch, $changes, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor DarkGray
}

function Show-Menu {
    Write-Host ''
    Write-Host '  ── 发布 ───────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host '   [1]  从列表选择文章发布' -ForegroundColor White
    Write-Host '   [2]  修改已发布文章（改完再发布）' -ForegroundColor Yellow
    Write-Host '   [3]  发布全部改动文章' -ForegroundColor White
    Write-Host '   [4]  新建文章' -ForegroundColor White
    Write-Host '   [5]  设置/更换文章封面并发布' -ForegroundColor White
    Write-Host ''
    Write-Host '  ── 工具 ───────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host '   [6]  只构建预览，不发布' -ForegroundColor Gray
    Write-Host '   [7]  查看最近发布日志' -ForegroundColor Gray
    Write-Host '   [8]  打开博客目录' -ForegroundColor Gray
    Write-Host '   [9]  打开线上网站' -ForegroundColor Gray
    Write-Host '  [10]  检查环境与仓库状态' -ForegroundColor Gray
    Write-Host '  [11]  创建/更新桌面快捷方式' -ForegroundColor Gray
    Write-Host ''
    Write-Host '   [0]  退出' -ForegroundColor DarkYellow
    Write-Host ''
}

function Pause-Menu {
    Write-Host ''
    Read-Host '按 Enter 返回主菜单' | Out-Null
}

function Invoke-Core {
    param([string[]]$CoreArgs)

    if (-not (Test-Path -LiteralPath $script:Core)) {
        Write-Host "找不到核心脚本：$script:Core" -ForegroundColor Red
        return
    }

    $argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Core) + $CoreArgs
    & $script:PowerShell @argsList
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        Write-Host ''
        Write-Host '操作完成。' -ForegroundColor Green
    } else {
        Write-Host ''
        Write-Host "操作结束，退出码：$code。请查看上方日志。" -ForegroundColor Yellow
    }
}

function Show-RecentLogs {
    $logDir = Join-Path $script:RepoRoot '.publish\logs'
    $logs = @(Get-ChildItem -LiteralPath $logDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($logs.Count -eq 0) {
        Write-Host '还没有发布日志。' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host '最近的发布日志：' -ForegroundColor Cyan
    $i = 1
    foreach ($log in ($logs | Select-Object -First 5)) {
        Write-Host ("  [{0}] {1}  {2}" -f $i, $log.LastWriteTime.ToString('MM-dd HH:mm'), $log.Name)
        $i++
    }
    Write-Host ''
    Write-Host '----- 最新日志末尾 -----' -ForegroundColor DarkGray
    Get-Content -LiteralPath $logs[0].FullName -Tail 30 | ForEach-Object { Write-Host $_ }
}

function Show-Status {
    Write-Host ''
    Write-Host '环境与仓库状态' -ForegroundColor Cyan
    Write-Host '────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ("仓库：{0}" -f $script:RepoRoot)
    Write-Host ("分支：{0}" -f (Get-Branch))
    try {
        $node = (& node --version 2>$null)
        $npm = (& npm.cmd --version 2>$null)
        $git = (& git --version 2>$null)
        Write-Host ("Node：{0}    npm：{1}" -f $node, $npm)
        Write-Host ("Git ：{0}" -f $git)
    } catch {
        Write-Host 'Node/npm/Git 检查失败，请确认环境变量。' -ForegroundColor Yellow
    }
    try {
        $last = (& git -C $script:RepoRoot log -1 --format='%h  %s' 2>$null)
        Write-Host ("最近提交：{0}" -f $last)
    } catch { }
    Write-Host ("待发布文章：{0} 篇" -f (Get-ChangeCount))
    Write-Host 'Twikoo：https://clouds-remain-twikoo.netlify.app/.netlify/functions/twikoo'
    Write-Host '线上站点：https://clouds-remain.github.io/'
}

function Install-Shortcut {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

    $exe = Join-Path $script:RepoRoot 'tools\CloudsRemainPublisher.exe'
    $target = $exe
    $iconLocation = "$exe,0"
    if (-not (Test-Path -LiteralPath $target)) {
        $target = Join-Path $script:RepoRoot 'publish.cmd'
        $iconLocation = "$script:Icon,0"
    }
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host "找不到启动文件：$target" -ForegroundColor Red
        return
    }

    $paths = @()
    if ($desktop -and (Test-Path -LiteralPath $desktop)) {
        $paths += (Join-Path $desktop 'Clouds-remain 发布中心.lnk')
    }
    if (Test-Path -LiteralPath $startDir) {
        $paths += (Join-Path $startDir 'Clouds-remain 发布中心.lnk')
    }
    if ($paths.Count -eq 0) {
        Write-Host '找不到桌面或开始菜单目录。' -ForegroundColor Red
        return
    }

    $shell = New-Object -ComObject WScript.Shell
    try {
        foreach ($shortcutPath in $paths) {
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $target
            $shortcut.Arguments = ''
            $shortcut.WorkingDirectory = $script:RepoRoot
            $shortcut.IconLocation = $iconLocation
            $shortcut.Description = 'Clouds-remain 博客发布中心'
            $shortcut.WindowStyle = 1
            $shortcut.Save()
            Write-Host "快捷方式已创建：$shortcutPath" -ForegroundColor Green
        }
        Write-Host '图标：' -NoNewline
        Write-Host $iconLocation -ForegroundColor Cyan
    } catch {
        Write-Host "创建快捷方式失败：$($_.Exception.Message)" -ForegroundColor Red
    } finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

# ---------------------------------------------------------------------------
# 主循环
# ---------------------------------------------------------------------------
try {
    while ($true) {
        Clear-Host
        Show-Banner
        Show-Menu
        $choice = (Read-Host '请选择').Trim()
        if ([string]::IsNullOrWhiteSpace($choice)) { continue }

        switch ($choice) {
            '1' { Invoke-Core @('-Pick') }
            '2' { Invoke-Core @('-Edit') }
            '3' { Invoke-Core @('-All') }
            '4' { Invoke-Core @('-New') }
            '5' { Invoke-Core @('-CoverInteractive') }
            '6' { Invoke-Core @('-BuildOnly') }
            '7' { Show-RecentLogs }
            '8' {
                try { Start-Process explorer.exe -ArgumentList $script:RepoRoot } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
            }
            '9' {
                try { Start-Process 'https://clouds-remain.github.io/' } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
            }
            '10' { Show-Status }
            '11' { Install-Shortcut }
            '0' {
                Write-Host ''
                Write-Host '已退出发布中心。' -ForegroundColor DarkGray
                break
            }
            default {
                Write-Host '无效选项，请重新选择。' -ForegroundColor Yellow
                Start-Sleep -Milliseconds 800
                continue
            }
        }

        if ($choice -eq '0') { break }
        Pause-Menu
    }
} catch {
    Write-Host ''
    Write-Host "发布中心发生错误：$($_.Exception.Message)" -ForegroundColor Red
    Read-Host '按 Enter 关闭' | Out-Null
}
