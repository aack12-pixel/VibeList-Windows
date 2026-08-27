param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$')]
    [string]$GitHubOwner,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Repository = "VibeList-Windows"
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceScript = Join-Path $projectDir "VibeList.ps1"
$launcherSource = Join-Path $projectDir "VibeList.Launcher.cs"
$iconFile = Join-Path $projectDir "VibeList.ico"
$outputExe = Join-Path $projectDir "VibeList.exe"
$hashFile = Join-Path $projectDir "VibeList.exe.sha256"
$scriptHashFile = Join-Path $projectDir "VibeList.ps1.sha256"
$zipFile = Join-Path $projectDir "VibeList-Windows-portable.zip"
$releaseDir = Join-Path $projectDir "release\VibeList"
$compiler = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

foreach ($required in @($sourceScript, $launcherSource, $iconFile, $compiler)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "필수 파일을 찾을 수 없습니다: $required" }
}

$apiUrl = "https://api.github.com/repos/$GitHubOwner/$Repository/releases/latest"
$temporaryDir = Join-Path $env:TEMP ("VibeListBuild-" + [guid]::NewGuid().ToString("N"))
$embeddedScript = Join-Path $temporaryDir "VibeList.ps1"

try {
    New-Item -ItemType Directory -Path $temporaryDir | Out-Null
    $scriptText = Get-Content -LiteralPath $sourceScript -Raw -Encoding UTF8
    $scriptText = $scriptText.Replace("__UPDATE_API_URL__", $apiUrl)
    $scriptText = [regex]::Replace($scriptText, 'https://api\.github\.com/repos/[^/\"'']+/[^/\"'']+/releases/latest', $apiUrl)
    [IO.File]::WriteAllText($embeddedScript, $scriptText, [Text.UTF8Encoding]::new($true))

    $compilerArgs = @(
        "/nologo", "/target:winexe", "/platform:anycpu", "/optimize+", "/codepage:65001",
        "/out:$outputExe", "/win32icon:$iconFile",
        "/reference:System.dll", "/reference:System.Core.dll", "/reference:System.Windows.Forms.dll",
        "/resource:$embeddedScript,VibeList.ps1", "/resource:$iconFile,VibeList.ico", $launcherSource
    )
    & $compiler $compilerArgs
    if ($LASTEXITCODE -ne 0) { throw "EXE 빌드에 실패했습니다: $LASTEXITCODE" }

    $hash = (Get-FileHash -LiteralPath $outputExe -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  VibeList.exe" | Set-Content -LiteralPath $hashFile -Encoding ASCII
    $scriptHash = (Get-FileHash -LiteralPath $sourceScript -Algorithm SHA256).Hash.ToLowerInvariant()
    "$scriptHash  VibeList.ps1" | Set-Content -LiteralPath $scriptHashFile -Encoding ASCII

    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
    Copy-Item -LiteralPath $outputExe -Destination (Join-Path $releaseDir "VibeList.exe") -Force
    Copy-Item -LiteralPath $sourceScript -Destination (Join-Path $releaseDir "VibeList.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $projectDir "VibeList.cmd") -Destination (Join-Path $releaseDir "VibeList.cmd") -Force
    Copy-Item -LiteralPath $iconFile -Destination (Join-Path $releaseDir "VibeList.ico") -Force
    Copy-Item -LiteralPath (Join-Path $projectDir "사용방법.txt") -Destination (Join-Path $releaseDir "사용방법.txt") -Force
    Compress-Archive -LiteralPath $releaseDir -DestinationPath $zipFile -Force

    Write-Output "GitHub API: $apiUrl"
    Write-Output "EXE: $outputExe"
    Write-Output "SHA256: $hashFile"
    Write-Output "SCRIPT SHA256: $scriptHashFile"
    Write-Output "ZIP: $zipFile"
} finally {
    if (Test-Path -LiteralPath $temporaryDir) {
        $resolvedTemp = (Resolve-Path -LiteralPath $temporaryDir).Path
        $tempRoot = (Resolve-Path -LiteralPath $env:TEMP).Path
        if ($resolvedTemp.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
    }
}
