# 版本生成脚本（本地与 GitHub CI 通用）
#
# 思路对齐 PiliPlus 的 lib/scripts/build.ps1：
#   - 版本名来源：-VersionName（GitHub Action 的版本输入）优先，否则读 pubspec.yaml 的
#     `version:` 行（本地发布的唯一事实源）
#   - build 号 = git 提交总数（git rev-list --count HEAD，单调递增不重复）
#   - Android 发布包在版本名后追加 9 位 commit hash，便于用户反馈定位
#   - beta 形态（-Beta）：版本固定 1.0-beta / 1，不追加 hash，配合
#     `--dart-define=BETA=true` 由 gradle 切成独立应用（见 docs/15）
#   - 生成 mtbbs_release.json，供 `flutter build --dart-define-from-file` 注入
#   - 导出 MTBBS_VERSION_NAME / MTBBS_VERSION_CODE / MTBBS_VERSION / MTBBS_BETA
#     环境变量，CI 下同时写入 GITHUB_ENV 供后续步骤使用（Inno Setup 安装包版本号也读它）
#
# 用法：
#   scripts/version.ps1                               # 桌面平台，版本名读 pubspec.yaml
#   scripts/version.ps1 android                       # Android（版本名带 hash 后缀）
#   scripts/version.ps1 android -VersionName 1.2.0    # 显式指定版本名（容忍 v 前缀）
#   scripts/version.ps1 android -Beta                 # beta 形态（固定 1.0-beta / 1）
param(
    [string]$Platform = '',
    [string]$VersionName = '',
    [switch]$Beta
)

$ErrorActionPreference = 'Stop'

# 与 android/app/build.gradle.kts 中 beta 分支硬编码的值保持一致
$BETA_VERSION_NAME = '1.0-beta'
$BETA_VERSION_CODE = 1

# 版本名格式：x.y.z，可带 -后缀（与 pubspec 的 semver 写法一致），用于校验 Action 输入
$VERSION_PATTERN = '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$'
# pubspec 的 version 行：只取 semver 前缀，丢弃 +build 段（build 号由 git 提交数决定）
$PUBSPEC_PATTERN = '^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)'

try {
    # 注意：PowerShell 变量名不区分大小写，内部变量不能叫 $versionName / $versionCode，
    # 那与 -VersionName 参数是同一个变量，赋值会把参数冲掉（踩过，CI 上表现为静默用 pubspec 版本）
    $verName = ''
    $verCode = 0

    if ($Beta) {
        # beta 形态：版本固定，不参与提交数派生，也不追加 hash
        $verName = $BETA_VERSION_NAME
        $verCode = $BETA_VERSION_CODE
    }
    else {
        if ([string]::IsNullOrWhiteSpace($VersionName)) {
            # 本地默认：从 pubspec.yaml 读取版本名
            # 支持 semver 预发布后缀（如 version: 1.0.0-pro+1 → 版本名 "1.0.0-pro"）
            foreach ($line in (Get-Content -Path 'pubspec.yaml' -Encoding UTF8)) {
                if ($line -match $PUBSPEC_PATTERN) {
                    $verName = $matches[1]
                    break
                }
            }
            if ($verName -eq '') {
                throw 'pubspec.yaml 中未找到 version 行'
            }
        }
        else {
            # 显式传入（GitHub Action 的版本输入）：容忍 v 前缀并严格校验格式，
            # 免得拼错后污染 APK 文件名与安装包版本号
            $verName = $VersionName.Trim()
            if ($verName.StartsWith('v')) {
                $verName = $verName.Substring(1)
            }
            if ($verName -notmatch $VERSION_PATTERN) {
                throw "版本名格式不合法（应为 x.y.z 或 x.y.z-后缀）：$verName"
            }
        }

        # build 号 = git 提交总数
        $verCode = [int](git rev-list --count HEAD).Trim()
    }

    # commit hash
    $commitHash = (git rev-parse HEAD).Trim()

    # Android 版本名追加短 hash（beta 版本号固定，不加）
    if ($Platform -eq 'android' -and -not $Beta) {
        $verName = "$verName-$($commitHash.Substring(0, 9))"
    }

    $buildTime = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds())
    $isBeta = if ($Beta) { 'true' } else { 'false' }

    # 生成 dart-define 文件（无 BOM，兼容 Windows PowerShell 5.1）
    $data = @{
        'mtbbs.name' = $verName
        'mtbbs.code' = $verCode
        'mtbbs.hash' = $commitHash
        'mtbbs.time' = $buildTime
    }
    $json = $data | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText(
        (Join-Path $PWD 'mtbbs_release.json'),
        $json,
        (New-Object System.Text.UTF8Encoding $false)
    )

    # 导出环境变量；CI 下写入 GITHUB_ENV 供后续步骤读取
    $env:MTBBS_VERSION_NAME = $verName
    $env:MTBBS_VERSION_CODE = "$verCode"
    $env:MTBBS_VERSION = "$verName+$verCode"
    $env:MTBBS_BETA = $isBeta

    if ($env:GITHUB_ENV) {
        @(
            "MTBBS_VERSION_NAME=$verName",
            "MTBBS_VERSION_CODE=$verCode",
            "MTBBS_VERSION=$verName+$verCode",
            "MTBBS_BETA=$isBeta"
        ) | Add-Content -Path $env:GITHUB_ENV
    }

    Write-Host "MTBBS_VERSION_NAME = $verName"
    Write-Host "MTBBS_VERSION_CODE = $verCode"
    Write-Host "MTBBS_BETA = $isBeta"
    Write-Host "mtbbs_release.json 已生成：$json"
}
catch {
    Write-Error "版本生成失败: $($_.Exception.Message)"
    exit 1
}
