# 构建产物溯源摘要脚本（本地与 GitHub CI 通用）
#
# 目的：把本次打包产出的「文件名 / 大小 / SHA256」打印到控制台，
#       并写入 GitHub Actions 的 Job Summary。凭 Hash 即可反查
#       「某个已发布的安装包是否由这次 Action 构建」——release 可溯源。
#
# 用法：
#   scripts/artifact_summary.ps1 -Title 'Android APK' -Patterns 'MTBBS_android_*.apk'
#   scripts/artifact_summary.ps1 -Title 'Windows 安装包' -Patterns 'MTBBS_windows_*.exe','MTBBS_windows_*.zip'
param(
    # 产物路径 / glob（可多个），匹配不到任何文件时直接失败
    [Parameter(Mandatory = $true)]
    [string[]]$Patterns,
    # 摘要标题（如 Android APK / Windows 安装包）
    [string]$Title = '构建产物'
)

$ErrorActionPreference = 'Stop'

# 收集产物：按完整路径去重，再按文件名排序，保证日志顺序稳定可对比
$collected = @{}
foreach ($p in $Patterns) {
    Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue | ForEach-Object {
        $collected[$_.FullName] = $_
    }
}
$files = @($collected.Values | Sort-Object Name)

if ($files.Count -eq 0) {
    Write-Error "未匹配到任何产物文件：$($Patterns -join ', ')"
    exit 1
}

# 版本 / 提交信息：环境变量由 scripts/version.ps1 写入 GITHUB_ENV
$commitHash = ''
if (Get-Command git -ErrorAction SilentlyContinue) {
    $out = & git rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { $commitHash = "$out".Trim() }
    # 非 git 仓库时 git 返回非零退出码：显式清零，避免把非零码带出本步骤
    $global:LASTEXITCODE = 0
}
$commitShow = if ($commitHash) { $commitHash } else { 'N/A' }

$runUrl = ''
if ($env:GITHUB_SERVER_URL -and $env:GITHUB_REPOSITORY -and $env:GITHUB_RUN_ID) {
    $runUrl = "$($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)"
}

# ---- 控制台输出 ----
Write-Host '============================================================'
Write-Host "  产物溯源摘要：$Title"
Write-Host '============================================================'
Write-Host "版本名 (MTBBS_VERSION_NAME) : $($env:MTBBS_VERSION_NAME)"
Write-Host "构建号 (MTBBS_VERSION_CODE) : $($env:MTBBS_VERSION_CODE)"
Write-Host "beta   (MTBBS_BETA)         : $($env:MTBBS_BETA)"
Write-Host "提交   (commit)             : $commitShow"
if ($runUrl) { Write-Host "运行   (run)                : $runUrl" }
Write-Host ''

$rows = @()
foreach ($f in $files) {
    $sha = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
    Write-Host "  $($f.Name)"
    Write-Host ("    大小    : {0} 字节 ({1} MB)" -f $f.Length, [math]::Round($f.Length / 1MB, 2))
    Write-Host "    SHA256  : $sha"
    $rows += [pscustomobject]@{ Name = $f.Name; Bytes = $f.Length; Sha = $sha }
}
Write-Host '============================================================'

# ---- Job Summary（Markdown，随本次运行记录持久保存）----
if ($env:GITHUB_STEP_SUMMARY) {
    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine("## 产物溯源摘要：$Title")
    [void]$md.AppendLine()
    [void]$md.AppendLine("- 版本名：``$($env:MTBBS_VERSION_NAME)``")
    [void]$md.AppendLine("- 构建号：``$($env:MTBBS_VERSION_CODE)``")
    [void]$md.AppendLine("- beta：``$($env:MTBBS_BETA)``")
    [void]$md.AppendLine("- commit：``$commitShow``")
    if ($runUrl) { [void]$md.AppendLine("- 运行：$runUrl") }
    [void]$md.AppendLine()
    [void]$md.AppendLine('| 产物 | 大小 (MB) | SHA256 |')
    [void]$md.AppendLine('|---|---|---|')
    foreach ($r in $rows) {
        [void]$md.AppendLine("| $($r.Name) | $([math]::Round($r.Bytes / 1MB, 2)) | ``$($r.Sha)`` |")
    }
    [void]$md.AppendLine()
    [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $md.ToString())
    Write-Host "已写入 Job Summary（$($rows.Count) 个产物）"
}

# 显式成功退出：避免前面 git 等原生命令的退出码干扰本步骤结果
exit 0
