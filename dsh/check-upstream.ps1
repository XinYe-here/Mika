# 自维护包:每天看一眼上游更新了什么(只读,不改任何东西)
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File D:\MikaBuild\check-upstream.ps1
#
# 输出:屏幕 + D:\MikaBuild\upstream-report.txt
# 说明:只 fetch 上游、看新版本和新提交,不合并、不编译、不推任何东西。

$ErrorActionPreference = 'Continue'  # git 往 stderr 写进度;不设 Stop,否则 PS5.1 会把它当致命错误
$repo = 'D:\Temp\mika-research'
$out = 'D:\MikaBuild\upstream-report.txt'

Set-Location $repo
git fetch origin main --tags --prune 2>&1 | Out-Null

$local = ConvertFrom-StringData (Get-Content "$repo\dsh\version.properties" -Raw -Encoding UTF8)
$syncedCommit = $local['upstreamCommit']
$syncedVersion = $local['upstreamVersion']

# 上游现在的版本号与最新提交
$gradle = git show origin/main:app/build.gradle.kts
$upVersion = ($gradle | Select-String -Pattern 'versionName = "([^"]+)"').Matches.Groups[1].Value
$upCode = ($gradle | Select-String -Pattern 'versionCode = (\d+)').Matches.Groups[1].Value
$upHead = (git rev-parse --short origin/main).Trim()

$lines = @()
$lines += "=== Mika 上游更新检查 $(Get-Date -Format 'yyyy-MM-dd HH:mm') ==="
$lines += "本地已同步: $syncedVersion (commit $syncedCommit)"
$lines += "上游最新  : $upVersion (versionCode $upCode, commit $upHead)"

if ($upVersion -ne $syncedVersion -or $upHead -ne $syncedCommit) {
    $lines += ""
    $lines += "*** 上游有更新,可以合并 ***"
    $lines += ""
    $lines += "新提交:"
    $range = if ($syncedCommit) { "$syncedCommit..origin/main" } else { 'origin/main' }
    $lines += (git log --oneline --no-decorate $range 2>&1 | Select-Object -First 40)
    $lines += ""
    $lines += "合并方式(在仓库里执行):"
    $lines += "  git checkout dsh/main"
    $lines += "  git rebase origin/main"
    $lines += "  # 改 dsh/version.properties:upstreamVersion / upstreamCode / upstreamCommit,rev +1"
    $lines += "  .\gradlew.bat :app:assemblePersonal"
    $lines += "  # 然后 gh release create 发到自己的 fork"
} else {
    $lines += ""
    $lines += "上游没有变化,不用合并。"
}

$lines | ForEach-Object { $_ }
$lines | Out-File $out -Encoding utf8
"（报告已写入 $out）"
