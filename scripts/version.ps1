# 版本生成脚本（本地与 GitHub CI 通用）
#
# 思路对齐 PiliPlus 的 lib/scripts/build.ps1：
#   - 版本名唯一事实源 = pubspec.yaml 的 `version:` 行（发布时手动改这里）
#   - build 号 = git 提交总数（git rev-list --count HEAD，单调递增不重复）
#   - Android 发布包在版本名后追加 9 位 commit hash，便于用户反馈定位
#   - 生成 mtbbs_release.json，供 `flutter build --dart-define-from-file` 注入
#   - 导出 MTBBS_VERSION_NAME / MTBBS_VERSION_CODE / MTBBS_VERSION 环境变量，
#     CI 下同时写入 GITHUB_ENV 供后续步骤使用（Inno Setup 安装包版本号也读它）
#
# 用法：
#   scripts/version.ps1               # Windows 等桌面平台
#   scripts/version.ps1 android       # Android（版本名带 hash 后缀）
param(
    [string]$Platform = ''
)

$ErrorActionPreference = 'Stop'

try {
    # 1. 从 pubspec.yaml 读取版本名（唯一事实源）
    $versionName = $null
    foreach ($line in (Get-Content -Path 'pubspec.yaml' -Encoding UTF8)) {
        if ($line -match '^\s*version:\s*([\d\.]+)') {
            $versionName = $matches[1]
            break
        }
    }
    if ($null -eq $versionName) {
        throw 'pubspec.yaml 中未找到 version 行'
    }

    # 2. build 号 = git 提交总数
    $versionCode = [int](git rev-list --count HEAD).Trim()

    # 3. commit hash
    $commitHash = (git rev-parse HEAD).Trim()

    # 4. Android 版本名追加短 hash
    if ($Platform -eq 'android') {
        $versionName = "$versionName-$($commitHash.Substring(0, 9))"
    }

    $buildTime = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds())

    # 5. 生成 dart-define 文件（无 BOM，兼容 Windows PowerShell 5.1）
    $data = @{
        'mtbbs.name' = $versionName
        'mtbbs.code' = $versionCode
        'mtbbs.hash' = $commitHash
        'mtbbs.time' = $buildTime
    }
    $json = $data | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText(
        (Join-Path $PWD 'mtbbs_release.json'),
        $json,
        (New-Object System.Text.UTF8Encoding $false)
    )

    # 6. 导出环境变量；CI 下写入 GITHUB_ENV 供后续步骤读取
    $env:MTBBS_VERSION_NAME = $versionName
    $env:MTBBS_VERSION_CODE = "$versionCode"
    $env:MTBBS_VERSION = "$versionName+$versionCode"

    if ($env:GITHUB_ENV) {
        @(
            "MTBBS_VERSION_NAME=$versionName",
            "MTBBS_VERSION_CODE=$versionCode",
            "MTBBS_VERSION=$versionName+$versionCode"
        ) | Add-Content -Path $env:GITHUB_ENV
    }

    Write-Host "MTBBS_VERSION_NAME = $versionName"
    Write-Host "MTBBS_VERSION_CODE = $versionCode"
    Write-Host "mtbbs_release.json 已生成：$json"
}
catch {
    Write-Error "版本生成失败: $($_.Exception.Message)"
    exit 1
}
