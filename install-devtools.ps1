#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$PSNativeCommandUseErrorActionPreference = $false
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not [Environment]::Is64BitProcess) {
    throw 'Run this script from a 64-bit PowerShell session.'
}
if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    throw 'Run elevated as the intended desktop user, not SYSTEM; WinGet and editor extensions are user-scoped.'
}
$operatingSystem = Get-CimInstance Win32_OperatingSystem
$windowsBuild = [int]$operatingSystem.BuildNumber
if ($operatingSystem.ProductType -ne 1 -or $windowsBuild -lt 19045 -or ($windowsBuild -ge 22000 -and $windowsBuild -lt 22631)) {
    throw 'This toolset requires Windows 10 22H2 or Windows 11 23H2 or newer; Docker Desktop does not support Windows Server.'
}
$script:rebootRequired = $false
$downloadDirectory = Join-Path $env:ProgramData 'LearningDevBox\Installers'
New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
Set-TimeZone -Id 'GMT Standard Time'

function Install-SignedPackage {
    param(
        [string] $Name,
        [string] $Uri,
        [string] $FileName,
        [string] $Signer,
        [string] $Arguments
    )
    $path = Join-Path $downloadDirectory $FileName
    Write-Output "Downloading: $Name"
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $path -TimeoutSec 300
    $signature = Get-AuthenticodeSignature -FilePath $path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch $Signer) {
        throw "Installer signature validation failed: $Name"
    }
    if ($FileName.EndsWith('.msi')) {
        $process = Start-Process msiexec.exe -ArgumentList "/i `"$path`" /qn /norestart $Arguments" -PassThru
    } else {
        $process = Start-Process -FilePath $path -ArgumentList $Arguments -PassThru
    }
    if (-not $process.WaitForExit(600000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$Name installer exceeded ten minutes."
    }
    $process.Refresh()
    if ($process.ExitCode -notin @(0, 3010, 1641)) {
        throw "$Name installer returned $($process.ExitCode)"
    }
    if ($process.ExitCode -in @(3010, 1641)) {
        $script:rebootRequired = $true
    }
    Remove-Item -LiteralPath $path
    Write-Output "Installed: $Name"
}

function Invoke-CheckedCommand {
    param(
        [string] $FilePath,
        [string[]] $Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath $($Arguments -join ' ') returned $LASTEXITCODE"
    }
}

function Initialize-WinGet {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        Write-Output 'Bootstrapping Windows Package Manager...' | Out-Host
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope AllUsers -Force | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope AllUsers -Force
        Import-Module Microsoft.WinGet.Client
        Repair-WinGetPackageManager -AllUsers | Out-Null
        $env:Path += ';' + (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
        $command = Get-Command winget.exe -ErrorAction Stop
    }
    Invoke-CheckedCommand -FilePath $command.Source -Arguments @('--version') | Out-Host
    return $command.Source
}

function Install-WinGetPackage {
    param(
        [string] $Id,
        [string] $Scope,
        [string] $InstallerType,
        [string] $Custom
    )
    $arguments = @(
        'install', '--id', $Id, '--exact', '--source', 'winget',
        '--architecture', 'x64', '--silent', '--no-upgrade',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    )
    if ($Scope) { $arguments += @('--scope', $Scope) }
    if ($InstallerType) { $arguments += @('--installer-type', $InstallerType) }
    if ($Custom) { $arguments += @('--custom', $Custom) }
    & $wingetPath @arguments | Out-Host
    $exitCode = $LASTEXITCODE
    # WinGet reports already-installed packages and reboot outcomes using HRESULTs.
    if ($exitCode -in @(3010, 1641, 0x8A150109, 0x8A15010B)) {
        $script:rebootRequired = $true
    } elseif ($exitCode -eq 0x8A15010A) {
        throw "Restart Windows and rerun the script to install $Id."
    } elseif ($exitCode -notin @(0, 0x8A15002B, 0x8A150061, 0x8A15010D)) {
        throw "WinGet installation failed for $Id (exit code $exitCode)."
    }
}

$wingetPath = Initialize-WinGet

if (-not (Test-Path 'C:\Program Files\Microsoft VS Code\Code.exe')) {
    Install-SignedPackage -Name 'Visual Studio Code' -Uri 'https://update.code.visualstudio.com/latest/win32-x64/stable' -FileName 'vscode.exe' -Signer 'O=Microsoft Corporation' -Arguments '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /MERGETASKS="!runcode,addcontextmenufiles,addcontextmenufolders,addtopath"'
}
if (-not (Test-Path 'C:\Program Files\Git\cmd\git.exe')) {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -TimeoutSec 60
    $asset = $release.assets | Where-Object { $_.name -match '^Git-[\d.]+-64-bit\.exe$' } | Select-Object -First 1
    if (-not $asset) { throw 'Stable Git x64 installer not found.' }
    Install-SignedPackage -Name 'Git' -Uri $asset.browser_download_url -FileName 'git.exe' -Signer 'Johannes Schindelin|Git for Windows' -Arguments '/VERYSILENT /NORESTART'
}
if (-not (Test-Path 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd')) {
    Install-SignedPackage -Name 'Azure CLI' -Uri 'https://aka.ms/installazurecliwindowsx64' -FileName 'azure-cli.msi' -Signer 'O=Microsoft Corporation' -Arguments ''
}
if (-not (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe')) {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -TimeoutSec 60
    $asset = $release.assets | Where-Object { $_.name -match '^PowerShell-[\d.]+-win-x64\.msi$' } | Select-Object -First 1
    if (-not $asset) { throw 'Stable PowerShell x64 installer not found.' }
    Install-SignedPackage -Name 'PowerShell 7' -Uri $asset.browser_download_url -FileName 'powershell.msi' -Signer 'O=Microsoft Corporation' -Arguments 'ADD_PATH=1 ENABLE_PSREMOTING=0 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1'
}

$githubCliPath = 'C:\Program Files\GitHub CLI\gh.exe'
if (-not (Test-Path $githubCliPath)) {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/cli/cli/releases/latest' -TimeoutSec 60
    $asset = $release.assets | Where-Object { $_.name -match '^gh_[\d.]+_windows_amd64\.msi$' } | Select-Object -First 1
    if (-not $asset) { throw 'Stable GitHub CLI x64 installer not found.' }
    Install-SignedPackage -Name 'GitHub CLI' -Uri $asset.browser_download_url -FileName 'github-cli.msi' -Signer 'O="?GitHub, Inc\."' -Arguments ''
}

$copilotCliDirectory = 'C:\Program Files\GitHub Copilot CLI'
$copilotCliPath = Join-Path $copilotCliDirectory 'copilot.exe'
if (-not (Test-Path $copilotCliPath)) {
    Install-SignedPackage -Name 'GitHub Copilot CLI' -Uri 'https://github.com/github/copilot-cli/releases/latest/download/copilot-x64.msi' -FileName 'copilot-cli.msi' -Signer 'O="?GitHub, Inc\."' -Arguments "ALLUSERS=1 INSTALLFOLDER=`"$copilotCliDirectory`""
}

$copilotAppPath = 'C:\Program Files\GitHub Copilot\github.exe'
if (-not (Test-Path $copilotAppPath)) {
    Install-SignedPackage -Name 'GitHub Copilot app' -Uri 'https://github.com/github/app/releases/latest/download/GitHub-Copilot-windows-x64.msi' -FileName 'copilot-app.msi' -Signer 'O="?GitHub, Inc\."' -Arguments ''
}

$pythonVersion = '3.14.10'
$pythonDirectory = 'C:\Program Files\Python314'
$pythonPath = Join-Path $pythonDirectory 'python.exe'
if (-not (Test-Path $pythonPath)) {
    Install-SignedPackage -Name 'Python' -Uri "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-amd64.exe" -FileName 'python.exe' -Signer 'O=Python Software Foundation' -Arguments "/quiet InstallAllUsers=1 TargetDir=`"$pythonDirectory`" PrependPath=1 Include_pip=1 Include_test=0 Include_launcher=1 InstallLauncherAllUsers=1"
}

$claudeDirectory = 'C:\Program Files\Claude Code'
$claudePath = Join-Path $claudeDirectory 'claude.exe'
if (-not (Test-Path $claudePath)) {
    $claudeBaseUri = 'https://downloads.claude.ai/claude-code-releases'
    $claudeVersion = (Invoke-RestMethod -Uri "$claudeBaseUri/latest" -TimeoutSec 60).Trim()
    if ($claudeVersion -notmatch '^\d+\.\d+\.\d+(-[\w.-]+)?$') {
        throw 'Invalid Claude Code release version.'
    }
    $manifest = Invoke-RestMethod -Uri "$claudeBaseUri/$claudeVersion/manifest.json" -TimeoutSec 60
    $checksum = $manifest.platforms.'win32-x64'.checksum
    if ($checksum -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'Claude Code x64 checksum not found.'
    }
    $downloadPath = Join-Path $downloadDirectory 'claude.exe'
    Invoke-WebRequest -UseBasicParsing -Uri "$claudeBaseUri/$claudeVersion/win32-x64/claude.exe" -OutFile $downloadPath -TimeoutSec 300
    if ((Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash -ne $checksum) {
        throw 'Claude Code checksum validation failed.'
    }
    $signature = Get-AuthenticodeSignature -FilePath $downloadPath
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O="?Anthropic') {
        throw 'Claude Code signature validation failed.'
    }
    New-Item -ItemType Directory -Path $claudeDirectory -Force | Out-Null
    Move-Item -LiteralPath $downloadPath -Destination $claudePath -Force
    Write-Output 'Installed: Claude Code'
}

foreach ($featureName in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName
    if ($feature.State -eq 'EnablePending') {
        $script:rebootRequired = $true
    } elseif ($feature.State -ne 'Enabled') {
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart
        if ($result.RestartNeeded) { $script:rebootRequired = $true }
    }
}

$wingetPackages = @(
    @{ Id = 'OpenJS.NodeJS.LTS'; Scope = 'machine' }
    @{ Id = 'astral-sh.uv'; Scope = 'machine' }
    @{ Id = 'Microsoft.Azd' }
    @{ Id = 'Hashicorp.Terraform'; Scope = 'machine' }
    @{ Id = 'Microsoft.DotNet.SDK.10'; Scope = 'machine' }
    @{ Id = 'Microsoft.WindowsTerminal'; Scope = 'user' }
    @{ Id = '7zip.7zip'; Scope = 'machine' }
    @{ Id = 'Microsoft.Azure.FunctionsCoreTools'; Scope = 'machine' }
    @{ Id = 'Microsoft.WSL'; InstallerType = 'wix' }
    @{ Id = 'Docker.DockerDesktop'; Scope = 'machine' }
    @{ Id = 'Kubernetes.kubectl'; Scope = 'machine' }
    @{ Id = 'GoLang.Go'; Scope = 'machine' }
    @{ Id = 'Microsoft.OpenJDK.25'; Scope = 'machine' }
    @{
        Id = 'Microsoft.VisualStudio.BuildTools'
        Scope = 'machine'
        Custom = '--wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    }
    @{ Id = 'Microsoft.SQLServerManagementStudio.22'; Scope = 'machine'; Custom = '--wait --norestart' }
)
foreach ($package in $wingetPackages) {
    Install-WinGetPackage @package
}

$npmDirectory = Join-Path $env:ProgramData 'LearningDevBox\npm'
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
foreach ($directory in @($copilotCliDirectory, $claudeDirectory, $npmDirectory)) {
    if ($directory -notin ($machinePath -split ';')) {
        $machinePath += ";$directory"
    }
}
[Environment]::SetEnvironmentVariable('Path', $machinePath, 'Machine')
# Refresh this process after MSI installers update PATH.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

$npmPath = (Get-Command npm.cmd -ErrorAction Stop).Source
$azuritePath = Join-Path $npmDirectory 'azurite.cmd'
if (-not (Test-Path $azuritePath)) {
    Invoke-CheckedCommand -FilePath $npmPath -Arguments @('install', '--global', '--prefix', $npmDirectory, 'azurite') | Out-Host
}

$codeCliPath = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
$vscodeExtensions = @(
    'ms-python.python'
    'ms-python.vscode-pylance'
    'ms-vscode.powershell'
    'ms-azuretools.vscode-bicep'
    'hashicorp.terraform'
    'ms-azuretools.azure-dev'
    'ms-vscode.azurecli'
    'ms-azuretools.vscode-azureresourcegroups'
    'ms-azuretools.vscode-azurefunctions'
    'ms-azuretools.vscode-azurestorage'
    'ms-vscode-remote.remote-containers'
    'github.vscode-github-actions'
    'github.vscode-pull-request-github'
    'dbaeumer.vscode-eslint'
    'esbenp.prettier-vscode'
    'redhat.vscode-yaml'
)
$installedExtensions = @(Invoke-CheckedCommand -FilePath $codeCliPath -Arguments @('--list-extensions'))
foreach ($extension in $vscodeExtensions) {
    if ($extension -notin $installedExtensions) {
        Invoke-CheckedCommand -FilePath $codeCliPath -Arguments @('--install-extension', $extension) | Out-Host
    }
}
$extensionVersions = @(Invoke-CheckedCommand -FilePath $codeCliPath -Arguments @('--list-extensions', '--show-versions'))
$missingExtensions = @($vscodeExtensions | Where-Object { $_ -notin ($extensionVersions -replace '@.*$', '') })
if ($missingExtensions.Count) {
    throw "VS Code extensions missing after installation: $($missingExtensions -join ', ')"
}

# CLI extensions belong to the account running this script.
$azureCliPath = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
$azureExtensions = Invoke-CheckedCommand -FilePath $azureCliPath -Arguments @('extension', 'list', '--query', '[].name', '-o', 'tsv', '--only-show-errors')
if ('azure-devops' -notin $azureExtensions) {
    Invoke-CheckedCommand -FilePath $azureCliPath -Arguments @('extension', 'add', '--name', 'azure-devops', '--only-show-errors') | Out-Null
}
Invoke-CheckedCommand -FilePath $githubCliPath -Arguments @('extension', 'install', 'github/gh-ado2gh')

$packageInventory = [ordered]@{}
foreach ($package in $wingetPackages) {
    $packageInventory[$package.Id] = @(Invoke-CheckedCommand -FilePath $wingetPath -Arguments @('list', '--id', $package.Id, '--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity'))
}
$dotnetPath = 'C:\Program Files\dotnet\dotnet.exe'
$dotnetSdks = @(Invoke-CheckedCommand -FilePath $dotnetPath -Arguments @('--list-sdks'))
if (-not ($dotnetSdks -match '^10\.')) {
    throw '.NET SDK 10 was not found after installation.'
}
$vswherePath = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$buildTools = Invoke-CheckedCommand -FilePath $vswherePath -Arguments @('-latest', '-products', 'Microsoft.VisualStudio.Product.BuildTools', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-format', 'json') | ConvertFrom-Json
if (-not $buildTools) {
    throw 'Visual Studio Build Tools with the C++ workload were not found. Add the Desktop development with C++ workload and rerun.'
}

$software = [ordered]@{
    vscode = (Get-Item 'C:\Program Files\Microsoft VS Code\Code.exe').VersionInfo.ProductVersion
    git = (Invoke-CheckedCommand -FilePath 'C:\Program Files\Git\cmd\git.exe' -Arguments @('--version'))
    azureCli = (Invoke-CheckedCommand -FilePath $azureCliPath -Arguments @('version', '--query', '"azure-cli"', '-o', 'tsv'))
    powershell = (Invoke-CheckedCommand -FilePath 'C:\Program Files\PowerShell\7\pwsh.exe' -Arguments @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()'))
    githubCli = (Invoke-CheckedCommand -FilePath $githubCliPath -Arguments @('--version'))
    copilotCli = (Invoke-CheckedCommand -FilePath $copilotCliPath -Arguments @('--version'))
    copilotApp = (Get-Item $copilotAppPath).VersionInfo.ProductVersion
    python = (Invoke-CheckedCommand -FilePath $pythonPath -Arguments @('--version'))
    pythonPip = (Invoke-CheckedCommand -FilePath $pythonPath -Arguments @('-m', 'pip', '--version'))
    azureDevopsCli = (Invoke-CheckedCommand -FilePath $azureCliPath -Arguments @('extension', 'show', '--name', 'azure-devops', '--query', 'version', '-o', 'tsv', '--only-show-errors'))
    ado2gh = (Invoke-CheckedCommand -FilePath $githubCliPath -Arguments @('ado2gh', '--version'))
    claudeCode = (Invoke-CheckedCommand -FilePath $claudePath -Arguments @('--version'))
    node = (Invoke-CheckedCommand -FilePath 'node.exe' -Arguments @('--version'))
    npm = (Invoke-CheckedCommand -FilePath $npmPath -Arguments @('--version'))
    uv = (Invoke-CheckedCommand -FilePath 'uv.exe' -Arguments @('--version'))
    azureDeveloperCli = (Invoke-CheckedCommand -FilePath 'azd.exe' -Arguments @('version'))
    terraform = (Invoke-CheckedCommand -FilePath 'terraform.exe' -Arguments @('version', '-json') | ConvertFrom-Json)
    dotnetSdks = $dotnetSdks
    azureFunctionsCoreTools = (Invoke-CheckedCommand -FilePath 'func.exe' -Arguments @('--version'))
    azurite = (Invoke-CheckedCommand -FilePath $azuritePath -Arguments @('--version'))
    dockerCli = (Invoke-CheckedCommand -FilePath 'docker.exe' -Arguments @('--version'))
    kubectl = (Invoke-CheckedCommand -FilePath 'kubectl.exe' -Arguments @('version', '--client=true', '--output=json') | ConvertFrom-Json)
    go = (Invoke-CheckedCommand -FilePath 'go.exe' -Arguments @('version'))
    java = (Invoke-CheckedCommand -FilePath 'java.exe' -Arguments @('--version'))
    visualStudioBuildTools = @($buildTools)
    wingetPackages = $packageInventory
    vscodeExtensions = $extensionVersions
    rebootRequired = $script:rebootRequired
    dockerRuntime = 'Not started or validated. Start Docker Desktop after any required reboot; hardware or nested virtualization must be enabled.'
    timezone = (Get-TimeZone).Id
    windows = (Get-CimInstance Win32_OperatingSystem).Caption
    rdpListening = [bool](Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue)
}
$software | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $env:ProgramData 'LearningDevBox\readiness.json') -Encoding UTF8
$software | ConvertTo-Json -Depth 8
if ($script:rebootRequired) {
    Write-Warning 'Restart Windows to finish setup. This script does not restart the PC automatically.'
}
