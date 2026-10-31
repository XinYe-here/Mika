# 自维护 Mika:同步上游 / 编译 / 发布(一条命令)
#
#   powershell -ExecutionPolicy Bypass -File D:\MikaBuild\sync-upstream.ps1                 # 只检查
#   powershell -ExecutionPolicy Bypass -File D:\MikaBuild\sync-upstream.ps1 -Merge -Build    # 合并 + 编译
#   powershell -ExecutionPolicy Bypass -File D:\MikaBuild\sync-upstream.ps1 -Merge -Build -Publish  # 再推到自己 fork 并发 Release
#
# 设计原则:
#   * 只在自己的分支 dsh/main 上动,永远不改上游;
#   * 出任何问题(冲突/测试失败/编译失败)就停下,已有的包不动;
#   * 版本号自己排:major.minor.rev;versionCode = major*10000+minor*100+rev,只增不减,保证能覆盖安装。

param(
    [switch]$Merge,
    [switch]$Build,
    [switch]$Publish,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Continue'  # git 往 stderr 写进度;不设 Stop,否则 PS5.1 会把它当致命错误
$repo = 'D:\Temp\mika-research'
$forkRepo = 'XinYe-here/Mika'
$dist = 'D:\MikaBuild\dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Set-Location $repo

function Info($m) { Write-Host "[dsh] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[dsh] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[dsh] $m" -ForegroundColor Red; exit 2 }

# ---------- 版本号文件 ----------
$propsPath = "$repo\dsh\version.properties"
function Read-Props {
    $h = @{}
    Get-Content $propsPath -Encoding UTF8 | Where-Object { $_ -match '=' -and $_ -notmatch '^\s*#' } | ForEach-Object {
        $k, $v = $_ -split '=', 2
        $h[$k.Trim()] = $v.Trim()
    }
    return $h
}
function Write-Props($h) {
    $text = @(
        '# 自维护包的版本号(这个文件只在 dsh/main 分支上,上游没有)',
        '# upstreamVersion / upstreamCode / upstreamCommit = 上一次同步的上游;rev 每发一次自编包 +1,只增不减。',
        "major=$($h['major'])",
        "minor=$($h['minor'])",
        "upstreamVersion=$($h['upstreamVersion'])",
        "upstreamCode=$($h['upstreamCode'])",
        "upstreamCommit=$($h['upstreamCommit'])",
        "rev=$($h['rev'])"
    ) -join "`n"
    [System.IO.File]::WriteAllText($propsPath, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# ---------- 看上游 ----------
Info 'fetch 上游…'
git fetch origin main --tags --prune 2>&1 | Out-Null
$props = Read-Props
$gradle = git show origin/main:app/build.gradle.kts
$upVersion = ($gradle | Select-String -Pattern 'versionName = "([^"]+)"').Matches.Groups[1].Value
$upCode = [int](($gradle | Select-String -Pattern 'versionCode = (\d+)').Matches.Groups[1].Value)
$upHead = (git rev-parse --short origin/main).Trim()

$changed = ($upVersion -ne $props['upstreamVersion']) -or ($upHead -ne $props['upstreamCommit'])
Info "本地已同步 $($props['upstreamVersion']) ($($props['upstreamCommit']))；上游 $upVersion ($upHead)"
if (-not $changed) { Info '上游没有新东西,不用动。'; exit 0 }

$range = if ($props['upstreamCommit']) { "$($props['upstreamCommit'])..origin/main" } else { 'origin/main' }
$newCommits = git log --oneline --no-decorate $range
Info '上游新提交:'
$newCommits | ForEach-Object { Write-Host "  $_" }

if (-not $Merge) { Info '只检查模式。要合并就加 -Merge（可再加 -Build / -Publish）'; exit 0 }

# ---------- 合并 ----------
$dirty = git status --porcelain
if ($dirty) { Fail "工作区不干净,先提交或清理再跑:`n$dirty" }

Info '切到 dsh/main 并 rebase 到上游…'
git checkout dsh/main 2>&1 | Out-Null
git rebase origin/main
if ($LASTEXITCODE -ne 0) {
    Fail "rebase 有冲突。手动解完后 `git rebase --continue`,再重跑本脚本。冲突文件:`n$(git diff --name-only --diff-filter=U)"
}
$props['upstreamVersion'] = $upVersion
$props['upstreamCode'] = "$upCode"
$props['upstreamCommit'] = $upHead
$props['rev'] = "$([int]$props['rev'] + 1)"
Write-Props $props
$newVersionCode = [int]$props['major'] * 10000 + [int]$props['minor'] * 100 + [int]$props['rev']
$newVersionName = "$($props['major']).$($props['minor']).$($props['rev'])"
Info "新版本号: $newVersionName (versionCode $newVersionCode)"

# 上游可能改了 MikaLinks 等我们自维护的地方:确认关键改动还在
$links = Get-Content "$repo\app\src\main\java\com\wangzan101\mika\about\MikaLinks.kt" -Raw
if ($links -notmatch [regex]::Escape($forkRepo)) {
    Warn "MikaLinks.kt 里没有 $forkRepo 了(上游可能重写了这个文件)。检查:检查更新是否还指向自己的 fork?"
}

# ---------- 测试 ----------
if (-not $SkipTests) {
    Info '跑我们改动相关的测试…'
    $env:JAVA_HOME = 'D:\itcourse\jdk17.0.2'
    $env:ANDROID_HOME = 'D:\Android\Sdk'
    $env:ANDROID_SDK_ROOT = 'D:\Android\Sdk'
    $env:GRADLE_USER_HOME = 'D:\gradle-home'
    & "$repo\gradlew.bat" :core:test --console=plain --no-daemon `
        --tests "com.wangzan101.mika.core.model.Leaked*" `
        --tests "com.wangzan101.mika.core.memory.*" `
        --tests "com.wangzan101.mika.core.agent.AgentLoopMemoryTest" 2>&1 | Select-Object -Last 10
    if ($LASTEXITCODE -ne 0) { Fail "测试没过,先别发版。修好再重跑。" }
    Info '测试通过。'
}

# ---------- 编译 ----------
$apk = $null
if ($Build) {
    Info '编译 personal 包(用我们自己的 key 签)…'
    & "$repo\gradlew.bat" :app:assemblePersonal --console=plain --no-daemon 2>&1 | Select-Object -Last 8
    if ($LASTEXITCODE -ne 0) { Fail '编译失败。' }
    $src = "$repo\app\build\outputs\apk\personal\app-personal.apk"
    if (-not (Test-Path $src)) { Fail "没找到 APK: $src" }
    $apk = Join-Path $dist "Mika-$newVersionName.apk"
    Copy-Item $src $apk -Force
    Info "APK: $apk ($([math]::Round((Get-Item $apk).Length/1MB,2)) MB)"
}

# ---------- 提交 / 推送 / 发版 ----------
git add -A 2>&1 | Out-Null
git -c user.name=xinzhang -c user.email=3199569817@qq.com commit -m "自维护:同步上游 $upVersion,版本 $newVersionName" 2>&1 | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Warn '没有需要提交的改动(版本文件可能没变)。' }

if ($Publish) {
    Info '推 dsh/main 到自己的 fork…'
    git push -f fork dsh/main 2>&1 | Select-Object -Last 3
    if ($LASTEXITCODE -ne 0) { Fail '推送失败(检查 git 凭据)。' }
    $tag = "v$newVersionName"
    $notes = @(
        "自维护包,基于上游 $upVersion。",
        "",
        "上游这次的改动:",
        ($newCommits | Select-Object -First 30 | ForEach-Object { "  - $_" } | Out-String).Trim(),
        "",
        "本次自维护改动:DSML 标记还原、记忆全量注入(见仓库分支 dsh/main)。",
        "安装:直接覆盖安装,对话/记忆/配对都会保留。"
    ) -join "`n"
    $notesFile = Join-Path $dist "release-notes-$tag.md"
    $notes | Out-File $notesFile -Encoding utf8
    if (Test-Path $apk) {
        gh release create $tag $apk --repo $forkRepo --title "Mika $newVersionName" --notes-file $notesFile 2>&1 | Select-Object -Last 3
    } else {
        gh release create $tag --repo $forkRepo --title "Mika $newVersionName" --notes-file $notesFile 2>&1 | Select-Object -Last 3
    }
    if ($LASTEXITCODE -eq 0) { Info "已发布: https://github.com/$forkRepo/releases/tag/$tag" } else { Fail '发布失败。' }
}

Info '完成。'
