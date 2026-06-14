$ErrorActionPreference = "Stop"

$DefaultUrl = if ($env:AIUSAGE_INSTALL_URL) {
    $env:AIUSAGE_INSTALL_URL
} else {
    "https://raw.githubusercontent.com/frittlechasm/aiusage/main/aiusage"
}

$Source = if ($env:AIUSAGE_INSTALL_SOURCE) { $env:AIUSAGE_INSTALL_SOURCE } else { $DefaultUrl }
$InstallDir = if ($env:AIUSAGE_INSTALL_DIR) {
    $env:AIUSAGE_INSTALL_DIR
} else {
    Join-Path $env:LOCALAPPDATA "Programs\aiusage\bin"
}
$NoPathUpdate = $env:AIUSAGE_NO_PATH_UPDATE -eq "1"

for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        { $_ -in @("--dir", "-Dir") } {
            $i++
            if ($i -ge $args.Count) { throw "aiusage install: --dir requires a value" }
            $InstallDir = $args[$i]
            continue
        }
        { $_ -like "--dir=*" } {
            $InstallDir = $_.Substring("--dir=".Length)
            continue
        }
        { $_ -in @("--source", "-Source") } {
            $i++
            if ($i -ge $args.Count) { throw "aiusage install: --source requires a value" }
            $Source = $args[$i]
            continue
        }
        { $_ -like "--source=*" } {
            $Source = $_.Substring("--source=".Length)
            continue
        }
        "--no-path-update" {
            $NoPathUpdate = $true
            continue
        }
        default {
            throw "aiusage install: unknown option: $($_)"
        }
    }
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$ScriptPath = Join-Path $InstallDir "aiusage"

if ($Source -match "^https?://") {
    Invoke-WebRequest -UseBasicParsing -Uri $Source -OutFile $ScriptPath
} elseif (Test-Path -LiteralPath $Source) {
    Copy-Item -LiteralPath $Source -Destination $ScriptPath -Force
} else {
    throw "aiusage install: source not found: $Source"
}

$CmdPath = Join-Path $InstallDir "aiusage.cmd"
$Ps1Path = Join-Path $InstallDir "aiusage.ps1"
Set-Content -LiteralPath $CmdPath -Encoding ASCII -Value @(
    "@echo off",
    "bash ""%~dp0aiusage"" %*"
)
Set-Content -LiteralPath $Ps1Path -Encoding ASCII -Value @(
    "& bash ""$ScriptPath"" @args",
    "exit `$LASTEXITCODE"
)

Write-Host "aiusage install: installed $ScriptPath"

if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    Write-Host "aiusage install: warning: bash was not found on PATH; install Git for Windows or use WSL"
}

if (-not $NoPathUpdate) {
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $PathParts = @()
    if ($UserPath) {
        $PathParts = $UserPath -split ";"
    }

    if ($PathParts -contains $InstallDir) {
        Write-Host "aiusage install: $InstallDir is already on user PATH"
    } else {
        $NewPath = if ($UserPath) { "$UserPath;$InstallDir" } else { $InstallDir }
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        $env:Path = "$env:Path;$InstallDir"
        Write-Host "aiusage install: added $InstallDir to user PATH"
        Write-Host "aiusage install: restart your terminal to use aiusage"
    }
} else {
    Write-Host "aiusage install: add $InstallDir to PATH to run aiusage from any terminal"
}
