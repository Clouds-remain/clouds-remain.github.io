<#
.SYNOPSIS
    一键发布 Hexo 文章：校验、构建、提交、同步、推送，失败时保留可恢复现场。

.DESCRIPTION
    默认行为：
      1. 找出 source/_posts 下所有改动过的 Markdown
      2. 校验 front matter 和本地图片
      3. 执行 npm run build（失败时回退到 hexo generate + pagefind）
      4. 只提交选中的文章和图片
      5. git pull --rebase（失败时回退到 ghproxy 镜像拉取）
      6. 再次构建（如果拉取带来了新提交）
      7. git push（失败时重试，并生成 patch / bundle 救援包）

    常用方式：
      .\tools\publish.ps1                 # 交互菜单
      .\tools\publish.ps1 -All            # 发布所有改动文章
      .\tools\publish.ps1 -File "文章标题.md"
      .\tools\publish.ps1 -DryRun         # 只构建和检查，不提交
      .\tools\publish.ps1 -NoPush         # 提交但不推送
      .\tools\publish.ps1 -Title "新文章" # 新建文章并打开编辑器
#>
[CmdletBinding()]
param(
    [string]$Title,
    [string[]]$File,
    [switch]$All,
    [switch]$New,
    [switch]$DryRun,
    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 基础路径
# ---------------------------------------------------------------------------
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:PostsDir = Join-Path $script:RepoRoot 'source\_posts'
$script:ImagesDir = Join-Path $script:RepoRoot 'source\images'
$script:PublishDir = Join-Path $script:RepoRoot '.publish'
$script:LogDir = Join-Path $script:PublishDir 'logs'
$script:RescueDir = Join-Path $script:PublishDir 'rescue'
$script:LockFile = Join-Path $script:PublishDir 'publish.lock'
$script:LogFile = Join-Path $script:LogDir ("publish-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:Git = $null
$script:Npm = $null
$script:Npx = $null
$script:Node = $null
$script:StartTime = Get-Date

New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $script:RescueDir | Out-Null

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch { }

# ---------------------------------------------------------------------------
# 日志与输出
# ---------------------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    $color = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        'STEP' { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
}

function Fail {
    param([string]$Message)
    throw $Message
}

# ---------------------------------------------------------------------------
# 工具链 fallback：PATH 中没有 node/git 时，尝试已知安装目录
# ---------------------------------------------------------------------------
function Add-ToolPath {
    param([string]$Path)
    if ((Test-Path -LiteralPath $Path) -and ($env:Path -notlike "*$Path*")) {
        $env:Path = "$Path;$env:Path"
    }
}

function Resolve-Tools {
    $nodeCandidates = @(
        'D:\Users\49161\AppData\Local\Programs\nodejs',
        'C:\Program Files\nodejs',
        (Join-Path $env:LOCALAPPDATA 'Programs\nodejs')
    )
    $gitCandidates = @(
        'D:\Users\49161\AppData\Local\Programs\PortableGit\cmd',
        'C:\Program Files\Git\cmd',
        'C:\Program Files (x86)\Git\cmd'
    )

    foreach ($p in $nodeCandidates) { Add-ToolPath $p }
    foreach ($p in $gitCandidates) { Add-ToolPath $p }

    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    $npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
    $git = Get-Command git.exe -ErrorAction SilentlyContinue

    if (-not $node -or -not $npm -or -not $npx) {
        Fail '找不到 Node.js/npm。请确认 Node.js 已安装，或把安装目录加入 PATH。'
    }
    if (-not $git) {
        Fail '找不到 Git。请确认 Git 已安装，或把 Git 的 cmd 目录加入 PATH。'
    }

    $script:Node = $node.Source
    $script:Npm = $npm.Source
    $script:Npx = $npx.Source
    $script:Git = $git.Source

    Write-Log ("Node  {0}" -f (& $script:Node --version)) 'INFO'
    Write-Log ("npm   {0}" -f (& $script:Npm --version)) 'INFO'
    Write-Log ("Git   {0}" -f (& $script:Git --version)) 'INFO'
}

function Initialize-Repo {
    if (-not (Test-Path -LiteralPath (Join-Path $script:RepoRoot 'package.json'))) {
        Fail "脚本没有放在博客仓库内：$script:RepoRoot"
    }
    if (-not (Test-Path -LiteralPath $script:PostsDir)) {
        Fail "找不到文章目录：$script:PostsDir"
    }

    $branch = (& $script:Git -C $script:RepoRoot branch --show-current 2>$null).Trim()
    if ($branch -ne 'main') {
        Fail "当前分支是 '$branch'，脚本只允许在 main 分支发布。请先切换到 main。"
    }
    $remote = (& $script:Git -C $script:RepoRoot remote get-url origin 2>$null).Trim()
    if (-not $remote) {
        Fail '当前仓库没有 origin 远程地址。'
    }
    Write-Log "仓库：$script:RepoRoot" 'INFO'
    Write-Log "远程：$remote" 'INFO'
}

function Acquire-Lock {
    if (Test-Path -LiteralPath $script:LockFile) {
        $oldPidText = (Get-Content -LiteralPath $script:LockFile -Raw -ErrorAction SilentlyContinue).Trim()
        $oldPid = 0
        if ([int]::TryParse($oldPidText, [ref]$oldPid)) {
            $proc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($proc) {
                Fail "另一个发布进程正在运行（PID $oldPid）。请等它结束，或删除 .publish/publish.lock。"
            }
        }
        Remove-Item -LiteralPath $script:LockFile -Force
    }
    Set-Content -LiteralPath $script:LockFile -Value $PID -Encoding ASCII
    Write-Log "已获取发布锁（PID $PID）" 'INFO'
}

function Release-Lock {
    if (Test-Path -LiteralPath $script:LockFile) {
        $lockedPid = (Get-Content -LiteralPath $script:LockFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($lockedPid -eq "$PID") {
            Remove-Item -LiteralPath $script:LockFile -Force
        }
    }
}

# ---------------------------------------------------------------------------
# 命令执行与回退
# ---------------------------------------------------------------------------
function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$Label
    )

    Write-Log ("执行：{0} {1}  ({2})" -f $FilePath, ($Arguments -join ' '), $Label) 'STEP'
    $oldErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $code = 1
    try {
        $output = & $FilePath @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorAction
    }
    if ($null -ne $output) {
        foreach ($line in $output) {
            $text = $line.ToString()
            Write-Host $text
            Add-Content -LiteralPath $script:LogFile -Value $text -Encoding UTF8
        }
    }
    if ($code -ne 0) {
        Write-Log ("{0} 退出码 {1}" -f $Label, $code) 'WARN'
    }
    return $code
}

function Invoke-Build {
    param([string]$Reason = '构建')

    # 依赖缺失时自动安装，优先 npm ci，失败再 npm install
    $hexoPackage = Join-Path $script:RepoRoot 'node_modules\hexo\package.json'
    if (-not (Test-Path -LiteralPath $hexoPackage)) {
        Write-Log 'node_modules 不完整，尝试 npm ci ...' 'WARN'
        $code = Invoke-Native $script:Npm @('ci') 'npm ci'
        if ($code -ne 0) {
            Write-Log 'npm ci 失败，回退到 npm install ...' 'WARN'
            $code = Invoke-Native $script:Npm @('install', '--registry=https://registry.npmmirror.com') 'npm install'
            if ($code -ne 0) { return $false }
        }
    }

    Write-Log "开始构建（$Reason）..." 'STEP'
    $code = Invoke-Native $script:Npm @('run', 'build') 'npm run build'

    if ($code -ne 0) {
        Write-Log 'npm run build 失败，回退到 hexo generate + pagefind ...' 'WARN'
        $null = Invoke-Native $script:Npx @('hexo', 'clean') 'hexo clean'
        $code = Invoke-Native $script:Npx @('hexo', 'generate') 'hexo generate'
        if ($code -eq 0) {
            $code = Invoke-Native $script:Npx @('pagefind', '--site', 'public') 'pagefind'
        }
    }

    $index = Join-Path $script:RepoRoot 'public\index.html'
    $pagefind = Join-Path $script:RepoRoot 'public\pagefind\pagefind.js'
    if ($code -ne 0) {
        Write-Log '构建失败，已停止发布。' 'ERROR'
        return $false
    }
    if (-not (Test-Path -LiteralPath $index) -or (Get-Item -LiteralPath $index).Length -lt 1000) {
        Write-Log '构建产物 public/index.html 不存在或异常。' 'ERROR'
        return $false
    }
    if (-not (Test-Path -LiteralPath $pagefind)) {
        Write-Log '搜索索引 public/pagefind/pagefind.js 不存在，停止发布。' 'ERROR'
        return $false
    }

    Write-Log '构建通过。' 'OK'
    return $true
}

# ---------------------------------------------------------------------------
# 文章选择与校验
# ---------------------------------------------------------------------------
function Resolve-PostPath {
    param([string]$Value)

    $candidate = $Value
    if (-not [IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $script:RepoRoot $candidate
    }
    if (-not (Test-Path -LiteralPath $candidate) -and -not $Value.EndsWith('.md')) {
        $candidate = Join-Path $script:PostsDir "$Value.md"
    }
    $full = [IO.Path]::GetFullPath($candidate)
    $postsFull = [IO.Path]::GetFullPath($script:PostsDir)
    if (-not $full.StartsWith($postsFull, [StringComparison]::OrdinalIgnoreCase)) {
        Fail "只能发布 source/_posts 下的文章：$Value"
    }
    return $full
}

function Get-ChangedPosts {
    $lines = @(& $script:Git -C $script:RepoRoot -c core.quotepath=false status --porcelain -- source/_posts 2>$null)
    $posts = @()
    foreach ($line in $lines) {
        if ($line.Length -lt 4) { continue }
        $path = $line.Substring(3).Trim()
        if ($path -match '^"(.*)"$') { $path = $Matches[1] }
        if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1].Trim('"') }
        if ($path -match '\.obsidian') { continue }
        if ($path -notmatch '\.md$') { continue }
        $full = Join-Path $script:RepoRoot $path
        $posts += $full
    }
    return @($posts | Select-Object -Unique)
}

function Select-Posts {
    if ($File -and $File.Count -gt 0) {
        $posts = @()
        foreach ($f in $File) { $posts += Resolve-PostPath $f }
        return @($posts | Select-Object -Unique)
    }

    $changed = Get-ChangedPosts
    if ($changed.Count -gt 0) {
        Write-Log ("检测到 {0} 篇改动文章。" -f $changed.Count) 'INFO'
        foreach ($p in $changed) { Write-Log ("  - {0}" -f (Split-Path $p -Leaf)) 'INFO' }
        return $changed
    }

    if ($All) {
        $allPosts = @(Get-ChildItem -LiteralPath $script:PostsDir -Filter '*.md' -File | Sort-Object LastWriteTime -Descending)
        if ($allPosts.Count -gt 0) {
            Write-Log '没有检测到 Git 改动，-All 将发布最近编辑的文章。' 'WARN'
            return @($allPosts[0].FullName)
        }
    }

    $latest = Get-ChildItem -LiteralPath $script:PostsDir -Filter '*.md' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        Write-Host ''
        Write-Host "没有检测到改动。最近编辑的是：$($latest.Name)" -ForegroundColor Yellow
        $answer = Read-Host '要发布这一篇吗？[Y/n]'
        if ($answer -notmatch '^[Nn]') { return @($latest.FullName) }
    }

    return @()
}

function Get-PostTitle {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [IO.Path]::GetFileNameWithoutExtension($Path) }
    $lines = @(Get-Content -LiteralPath $Path -TotalCount 40 -Encoding UTF8)
    foreach ($line in $lines) {
        if ($line -match '^title:\s*(.+?)\s*$') {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return [IO.Path]::GetFileNameWithoutExtension($Path)
}

function Test-Posts {
    param([string[]]$Posts)

    if (-not $Posts -or $Posts.Count -eq 0) {
        Fail '没有选择任何文章。'
    }

    foreach ($post in $Posts) {
        if (-not (Test-Path -LiteralPath $post)) {
            Write-Log ("将删除文章：{0}" -f $post) 'INFO'
            continue
        }
        $lines = @(Get-Content -LiteralPath $post -TotalCount 40 -Encoding UTF8)
        if ($lines.Count -lt 2 -or $lines[0].TrimStart([char]0xFEFF).Trim() -ne '---') {
            Fail "文章缺少 front matter（文件开头必须是 ---）：$post"
        }
        $hasTitle = $false
        foreach ($line in $lines) {
            if ($line -match '^title:\s*\S') { $hasTitle = $true; break }
        }
        if (-not $hasTitle) {
            Fail "文章 front matter 缺少 title：$post"
        }
        $hasDate = $false
        foreach ($line in $lines) {
            if ($line -match '^date:\s*\S') { $hasDate = $true; break }
        }
        if (-not $hasDate) {
            Write-Log ("提示：{0} 没有 date，Hexo 会使用文件时间。" -f (Split-Path $post -Leaf)) 'WARN'
        }
    }
}

function Get-RelatedImages {
    param([string[]]$Posts)

    $images = @()
    foreach ($post in $Posts) {
        if (-not (Test-Path -LiteralPath $post)) { continue }
        $content = Get-Content -LiteralPath $post -Raw -Encoding UTF8
        $matches = [regex]::Matches($content, '!\[[^\]]*\]\((/images/[^)\s]+)\)')
        foreach ($m in $matches) {
            $rel = $m.Groups[1].Value.TrimStart('/').Replace('/', '\')
            $full = Join-Path $script:RepoRoot $rel
            if (-not (Test-Path -LiteralPath $full)) {
                Fail "文章引用了不存在的图片：$($m.Groups[1].Value)"
            }
            $images += $full
        }
    }
    return @($images | Select-Object -Unique)
}

# ---------------------------------------------------------------------------
# 新建文章
# ---------------------------------------------------------------------------
function New-BlogPost {
    $name = $Title
    if (-not $name) { $name = Read-Host '文章标题' }
    $name = $name.Trim()
    if (-not $name) { Fail '标题不能为空。' }

    $safe = $name
    foreach ($ch in [IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace($ch, '-')
    }
    $safe = $safe.Trim().TrimEnd('.')
    if (-not $safe) { Fail '标题无法转换为合法文件名。' }

    $path = Join-Path $script:PostsDir "$safe.md"
    if (Test-Path -LiteralPath $path) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $path = Join-Path $script:PostsDir "$safe-$stamp.md"
    }

    $date = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $yamlTitle = $name.Replace('\', '\\').Replace('"', '\"')
    $body = "---`r`ntitle: `"$yamlTitle`"`r`ndate: $date`r`ntags:`r`n---`r`n`r`n"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($path, $body, $utf8)

    Write-Log "已创建：$path" 'OK'
    Write-Log '请写完后重新运行脚本，选择「发布已修改的文章」。' 'INFO'

    try {
        Start-Process "obsidian://open?path=$([Uri]::EscapeDataString($path))"
        Write-Log '已尝试用 Obsidian 打开。' 'INFO'
    } catch {
        try {
            Start-Process notepad.exe -ArgumentList $path
            Write-Log 'Obsidian 未打开，已回退到记事本。' 'WARN'
        } catch {
            Write-Log "请手动打开：$path" 'WARN'
        }
    }
}

# ---------------------------------------------------------------------------
# Git 操作
# ---------------------------------------------------------------------------
function Get-RemoteSlug {
    $remote = (& $script:Git -C $script:RepoRoot remote get-url origin 2>$null).Trim()
    if ($remote -match 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?$') {
        return @($Matches[1], ($Matches[2] -replace '\.git$', ''))
    }
    return $null
}

function Invoke-Pull {
    $env:GCM_INTERACTIVE = 'never'
    $env:GIT_TERMINAL_PROMPT = '0'

    $code = Invoke-Native $script:Git @('-C', $script:RepoRoot, 'pull', '--rebase', 'origin', 'main') 'git pull --rebase'
    if ($code -eq 0) { return $true }

    $null = & $script:Git -C $script:RepoRoot rebase --abort 2>$null
    Write-Log '直连拉取失败，尝试 ghproxy 镜像拉取 ...' 'WARN'
    $slug = Get-RemoteSlug
    if (-not $slug) {
        Write-Log '无法解析 GitHub 仓库地址，跳过镜像回退。' 'WARN'
        return $false
    }

    $mirrorUrl = "https://ghproxy.net/https://github.com/$($slug[0])/$($slug[1]).git"
    $null = & $script:Git -C $script:RepoRoot remote remove __publish_mirror 2>$null
    $null = & $script:Git -C $script:RepoRoot remote add __publish_mirror $mirrorUrl 2>$null

    try {
        $code = Invoke-Native $script:Git @('-C', $script:RepoRoot, 'fetch', '__publish_mirror', 'main') 'git fetch mirror'
        if ($code -ne 0) { return $false }

        $code = Invoke-Native $script:Git @('-C', $script:RepoRoot, 'rebase', '__publish_mirror/main') 'git rebase mirror/main'
        if ($code -ne 0) {
            $null = & $script:Git -C $script:RepoRoot rebase --abort 2>$null
            Write-Log '镜像拉取后发生冲突，已中止 rebase；本地提交仍然保留。' 'ERROR'
            return $false
        }

        $mirrorHead = (& $script:Git -C $script:RepoRoot rev-parse __publish_mirror/main).Trim()
        $null = & $script:Git -C $script:RepoRoot update-ref refs/remotes/origin/main $mirrorHead 2>$null
        return $true
    } finally {
        $null = & $script:Git -C $script:RepoRoot remote remove __publish_mirror 2>$null
    }
}

function Save-RescueBundle {
    param([string]$Reason)

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target = Join-Path $script:RescueDir $stamp
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    $null = & $script:Git -C $script:RepoRoot format-patch -o $target 'origin/main..HEAD' 2>$null
    $bundle = Join-Path $target 'local-commits.bundle'
    $null = & $script:Git -C $script:RepoRoot bundle create $bundle 'origin/main..HEAD' 2>$null

    Write-Log "推送失败：$Reason" 'ERROR'
    Write-Log "本地提交没有丢失，救援文件在：$target" 'WARN'
    Write-Log '恢复方式：网络恢复后运行 git push origin main；或把 .publish/rescue 下的 patch 发给我。' 'WARN'
}

function Invoke-Push {
    $env:GCM_INTERACTIVE = 'never'
    $env:GIT_TERMINAL_PROMPT = '0'
    for ($i = 1; $i -le 3; $i++) {
        $code = Invoke-Native $script:Git @('-C', $script:RepoRoot, 'push', 'origin', 'main') "git push（第 $i 次）"
        if ($code -eq 0) { return $true }
        if ($i -lt 3) {
            Write-Log "推送失败，$($i * 5) 秒后重试 ..." 'WARN'
            Start-Sleep -Seconds ($i * 5)
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# 菜单
# ---------------------------------------------------------------------------
function Show-Menu {
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '  Clouds-remain 一键发布' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '  1. 发布已修改的文章'
    Write-Host '  2. 新建文章（创建后打开编辑器）'
    Write-Host '  3. 只构建预览，不发布'
    Write-Host '  4. 退出'
    Write-Host ''
    return (Read-Host '请选择 [1-4]')
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
try {
    Write-Log '========================================' 'STEP'
    Write-Log '开始发布流程' 'STEP'
    Write-Log '========================================' 'STEP'

    Resolve-Tools
    Initialize-Repo
    Acquire-Lock

    $mode = 'publish'
    if (-not $Title -and -not $New -and -not $File -and -not $All -and -not $DryRun -and -not $NoPush) {
        $choice = Show-Menu
        switch ($choice) {
            '1' { $mode = 'publish' }
            '2' { New-BlogPost; return }
            '3' { $mode = 'build-only' }
            default { Write-Log '已退出。' 'INFO'; return }
        }
    }

    if ($Title -or $New) {
        New-BlogPost
        return
    }

    if ($mode -eq 'build-only') {
        if (Invoke-Build '仅构建') {
            Write-Log '构建成功，未提交、未推送。' 'OK'
        } else {
            exit 1
        }
        return
    }

    $posts = Select-Posts
    if (-not $posts -or $posts.Count -eq 0) {
        Write-Log '没有需要发布的文章。' 'WARN'
        return
    }

    Test-Posts $posts
    $images = Get-RelatedImages $posts

    $titles = @()
    foreach ($post in $posts) {
        if (Test-Path -LiteralPath $post) { $titles += Get-PostTitle $post }
    }
    $commitTitle = if ($titles.Count -eq 1) { $titles[0] } else { "$($posts.Count) 篇文章" }

    if ($DryRun) {
        Write-Log 'DryRun：只构建和检查，不提交、不推送。' 'WARN'
        if (-not (Invoke-Build 'DryRun 构建')) { exit 1 }
        Write-Log 'DryRun 通过。' 'OK'
        return
    }

    # 构建必须发生在提交之前，失败时工作区保持原样
    if (-not (Invoke-Build '提交前构建')) {
        Write-Log '构建失败，未提交任何内容。请修复后重试。' 'ERROR'
        exit 1
    }

    # 只 add 选中的文章和文章引用的本地图片
    $stagePaths = @($posts + $images)
    $relative = @()
    foreach ($p in $stagePaths) {
        $rel = $p.Substring($script:RepoRoot.Length).TrimStart([char[]]@('\', '/'))
        $relative += $rel
    }
    $relative = @($relative | Select-Object -Unique)

    if (-not (Get-Command $script:Git)) { Fail 'Git 不可用。' }
    $code = Invoke-Native $script:Git (@('-C', $script:RepoRoot, 'add', '--') + $relative) 'git add'
    if ($code -ne 0) { Fail 'git add 失败。' }

    & $script:Git -C $script:RepoRoot diff --cached --quiet 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log '暂存区没有变更，可能文章内容与已提交版本一致。' 'WARN'
        return
    }

    $message = if ($titles.Count -eq 1) { "post: $commitTitle" } else { "posts: $commitTitle" }

    $userName = (& $script:Git -C $script:RepoRoot config user.name 2>$null).Trim()
    $userEmail = (& $script:Git -C $script:RepoRoot config user.email 2>$null).Trim()
    if (-not $userName) { $null = & $script:Git -C $script:RepoRoot config user.name 'Clouds-remain' }
    if (-not $userEmail) { $null = & $script:Git -C $script:RepoRoot config user.email 'Clouds-remain@users.noreply.github.com' }

    $code = Invoke-Native $script:Git @('-C', $script:RepoRoot, 'commit', '-m', $message) 'git commit'
    if ($code -ne 0) { Fail 'git commit 失败，请检查 Git 用户配置或冲突。' }

    $commitSha = (& $script:Git -C $script:RepoRoot rev-parse HEAD).Trim()
    Write-Log "已提交：$commitSha" 'OK'

    if ($NoPush) {
        Write-Log '已按 -NoPush 停止，未拉取、未推送。' 'WARN'
        return
    }

    Write-Log '同步远端 ...' 'STEP'
    if (-not (Invoke-Pull $commitSha)) {
        Write-Log '无法同步远端；本地提交已保留，未推送。' 'ERROR'
        Save-RescueBundle '拉取远端失败'
        exit 3
    }

    $afterHead = (& $script:Git -C $script:RepoRoot rev-parse HEAD).Trim()
    if ($afterHead -ne $commitSha) {
        Write-Log '拉取带来了新提交，重新构建 ...' 'WARN'
        if (-not (Invoke-Build '同步后构建')) {
            Write-Log '同步后构建失败；本地提交保留，未推送。' 'ERROR'
            exit 1
        }
    }

    Write-Log '推送到 GitHub ...' 'STEP'
    if (-not (Invoke-Push)) {
        Save-RescueBundle 'git push 连续失败'
        exit 4
    }

    $repoUrl = 'https://github.com/Clouds-remain/clouds-remain.github.io'
    Write-Log '推送成功。' 'OK'
    Write-Log "提交：$commitSha" 'INFO'
    Write-Log "Actions：$repoUrl/actions" 'INFO'
    Write-Log 'GitHub Actions 会自动构建并部署。' 'INFO'
    Write-Log ("耗时：{0:N1} 秒" -f ((Get-Date) - $script:StartTime).TotalSeconds) 'INFO'
} catch {
    Write-Log ("发布失败：{0}" -f $_.Exception.Message) 'ERROR'
    Write-Log ("日志：{0}" -f $script:LogFile) 'INFO'
    exit 1
} finally {
    Release-Lock
}
