---
title: ps-devtools
description: PowerShell provisioning script for a Windows developer workstation with Azure, containers, languages, and AI coding tools.
---

## Overview

`ps-devtools` provisions a Windows developer workstation using one PowerShell
script: [install-devtools.ps1](./install-devtools.ps1). It combines signed vendor
installers, Windows Package Manager (WinGet), npm, Windows optional features, and
editor extensions to prepare a broad development toolset.

Use it for a development or learning machine where you intend to install the
entire toolset. It is not a minimal package installer, a configuration management
system, or proof that every installed service is ready to run.

> [!WARNING]
> Review the script before running it. It requires administrator access, installs
> software, accepts package and source agreements for WinGet packages, enables
> Windows features, changes the machine PATH, and sets the time zone to
> `GMT Standard Time` (UK time, including daylight saving). Use a disposable
> development machine or take an appropriate backup first.

## Contents

* [Requirements](#requirements)
* [Quick start](#quick-start)
* [Installed tools](#installed-tools)
* [Editor and CLI extensions](#editor-and-cli-extensions)
* [Installation workflow](#installation-workflow)
* [Outputs and machine changes](#outputs-and-machine-changes)
* [After installation](#after-installation)
* [Rerunning and customization](#rerunning-and-customization)
* [Troubleshooting](#troubleshooting)
* [Development and contributions](#development-and-contributions)
* [Limitations](#limitations)
* [License](#license)

## Requirements

* An x64 Windows desktop installation:
  * Windows 10 22H2, build 19045 or later in the Windows 10 build range
  * Windows 11 23H2, build 22631 or later
* A 64-bit Windows PowerShell 5.1 or newer session
* Administrator privileges for the intended desktop user
* Internet access to vendor downloads, GitHub releases, the PowerShell Gallery,
  WinGet sources, the npm registry, and extension distribution services
* Enough disk space and time for the complete toolset, including Visual Studio
  Build Tools, SQL Server Management Studio, language SDKs, and Docker Desktop
* Hardware virtualization, or nested virtualization in a VM, for the intended
  WSL/container workflow

Windows Server, a 32-bit PowerShell process, and execution as `SYSTEM` are rejected
by the script. Run elevated as the desktop user who will use the tools: editor
and CLI extensions are installed for the executing account.

These are the script's platform checks, not a guarantee of current vendor support.
Individual tools can impose additional operating-system, hardware, license, or
account requirements. In particular, check the current
[Docker Desktop Windows requirements](https://docs.docker.com/desktop/setup/install/windows-install/)
before preparing a container-development machine.

## Quick start

### 1. Obtain and inspect the script

If Git is already available:

```powershell
git clone https://github.com/siyakhumalo-ms/ps-devtools.git
Set-Location .\ps-devtools
Get-Content .\install-devtools.ps1
```

Alternatively, download the script without executing it:

```powershell
Invoke-WebRequest -UseBasicParsing `
    -Uri 'https://raw.githubusercontent.com/siyakhumalo-ms/ps-devtools/main/install-devtools.ps1' `
    -OutFile .\install-devtools.ps1
Get-Content .\install-devtools.ps1
```

For a reproducible review, obtain the file from a specific commit rather than the
moving `main` branch.

### 2. Run from an elevated 64-bit PowerShell session

Open Windows PowerShell or PowerShell using **Run as administrator** as your
intended desktop user. Change to the directory containing the reviewed script:

```powershell
.\install-devtools.ps1
```

The script has no command-line parameters, package-selection switch, dry-run mode,
or unattended-account provisioning option. It installs the complete configured
toolset.

If execution policy blocks a file you downloaded, inspect it first and follow your
organization's approved policy. Where permitted, you can remove its downloaded-file
mark with:

```powershell
Unblock-File -LiteralPath .\install-devtools.ps1
```

Unblocking a file does not override an enforced execution policy or sign the script.

### 3. Inspect the result

On successful completion, the script prints a JSON inventory and writes the same
report to:

```text
%ProgramData%\LearningDevBox\readiness.json
```

Read the report in PowerShell:

```powershell
$reportPath = Join-Path $env:ProgramData 'LearningDevBox\readiness.json'
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
$report | Format-List
$report.rebootRequired
```

If a restart is required, the script warns you. It does not explicitly restart
Windows. Restart when appropriate, then complete the manual checks below.

## Installed tools

### Direct vendor downloads

These tools are installed when their expected executable is absent at the path
checked by the script. Existing installations at those paths are not upgraded.

| Tool                | Selection or purpose                                    |
|---------------------|---------------------------------------------------------|
| Visual Studio Code  | Latest stable x64 system installer                      |
| Git for Windows     | Latest stable GitHub release, 64-bit installer           |
| Azure CLI           | Vendor's x64 Windows MSI                                |
| PowerShell 7        | Latest stable GitHub release, x64 MSI                    |
| GitHub CLI          | Latest stable GitHub release, amd64 MSI                  |
| GitHub Copilot CLI  | Latest x64 release MSI                                  |
| GitHub Copilot app  | Latest x64 Windows release MSI                          |
| Python              | Pinned to 3.14.10, with pip and the all-users launcher    |
| Claude Code         | Latest release selected from the vendor's release feed  |

The Python executable is expected under `C:\Program Files\Python314`.
Claude Code is placed under `C:\Program Files\Claude Code`.
Availability of the pinned Python release and changing upstream assets must be
checked when maintaining the script; versions are not resolved from a lockfile.

Direct installer downloads require a valid Authenticode signature and a matching
expected publisher. Claude Code additionally requires a SHA-256 checksum matching
the vendor's manifest and a valid publisher signature. This is not a claim that
the repository signs its own script or independently audits downloaded software.

### WinGet packages

WinGet is bootstrapped if it is missing, using `Microsoft.WinGet.Client` from the
PowerShell Gallery and `Repair-WinGetPackageManager -AllUsers`.

The following exact package IDs are installed from the `winget` source with x64
architecture, silent mode, disabled interactivity, accepted agreements, and
`--no-upgrade`. Most use machine scope; exceptions are noted.

| Package ID                               | Purpose or installation detail                         |
|------------------------------------------|--------------------------------------------------------|
| `OpenJS.NodeJS.LTS`                       | Node.js LTS and npm                                    |
| `astral-sh.uv`                           | Python package and project manager                     |
| `Microsoft.Azd`                          | Azure Developer CLI; no explicit scope override        |
| `Hashicorp.Terraform`                    | Infrastructure as code                                 |
| `Microsoft.DotNet.SDK.10`                | .NET 10 SDK                                            |
| `Microsoft.WindowsTerminal`              | Windows Terminal; user scope                           |
| `7zip.7zip`                              | Archive utility                                        |
| `Microsoft.Azure.FunctionsCoreTools`     | Local Azure Functions tooling                          |
| `Microsoft.WSL`                          | WSL package; `wix` installer, no explicit scope override |
| `Docker.DockerDesktop`                   | Docker Desktop                                         |
| `Kubernetes.kubectl`                     | Kubernetes command-line client                         |
| `GoLang.Go`                              | Go toolchain                                           |
| `Microsoft.OpenJDK.25`                   | Microsoft OpenJDK 25                                   |
| `Microsoft.VisualStudio.BuildTools`      | C++ workload with recommended components               |
| `Microsoft.SQLServerManagementStudio.22` | SQL Server Management Studio 22                        |

SQL Server Management Studio is a management client. The script does not install
a SQL Server database engine.

### npm package and Windows features

* Azurite, the local Azure Storage emulator, is installed with npm under
  `%ProgramData%\LearningDevBox\npm` if its expected command is missing.
* `Microsoft-Windows-Subsystem-Linux` and `VirtualMachinePlatform` are enabled
  without an explicit automatic restart.

The script does not install a Linux distribution, start Azurite, or configure a
Kubernetes cluster.

## Editor and CLI extensions

### Visual Studio Code

The script installs missing extension IDs for the account running it and verifies
that every configured ID appears in the final extension list.

* Python and PowerShell:
  * `ms-python.python`
  * `ms-python.vscode-pylance`
  * `ms-vscode.powershell`
* Azure and infrastructure:
  * `ms-azuretools.vscode-bicep`
  * `hashicorp.terraform`
  * `ms-azuretools.azure-dev`
  * `ms-vscode.azurecli`
  * `ms-azuretools.vscode-azureresourcegroups`
  * `ms-azuretools.vscode-azurefunctions`
  * `ms-azuretools.vscode-azurestorage`
* Containers and GitHub:
  * `ms-vscode-remote.remote-containers`
  * `github.vscode-github-actions`
  * `github.vscode-pull-request-github`
* Formatting and configuration:
  * `dbaeumer.vscode-eslint`
  * `esbenp.prettier-vscode`
  * `redhat.vscode-yaml`

### Command-line extensions

* Azure CLI: `azure-devops`, installed if not already listed
* GitHub CLI: `github/gh-ado2gh`, requested on each run

Installing migration tooling does not perform an Azure DevOps-to-GitHub migration.
Any required authentication and migration configuration are separate steps.

## Installation workflow

The script runs sequentially and stops on unhandled errors:

1. Check PowerShell, elevation, process architecture, account, and Windows build.
2. Create the installer download directory and set the time zone.
3. Locate or bootstrap WinGet.
4. Install missing direct-download tools, checking signatures and the Claude Code
   checksum.
5. Enable WSL-related Windows features and install the WinGet package list.
6. Add configured tool directories to the machine PATH and refresh the current
   process PATH.
7. Install Azurite and missing VS Code extensions, then configure CLI extensions.
8. Gather installed-package and tool-version information, verify .NET 10 and the
   C++ Build Tools workload, and write the readiness report.

Direct executable/MSI installers have a ten-minute wait limit per installer;
direct downloads have their own timeouts. This is not an overall run timeout, and
WinGet or extension installations can take longer.

## Outputs and machine changes

* `%ProgramData%\LearningDevBox\Installers` holds downloads while they are being
  installed. Successful direct installers are removed; failed attempts can leave
  files behind.
* `%ProgramData%\LearningDevBox\npm` contains the Azurite installation.
* `%ProgramData%\LearningDevBox\readiness.json` records tool versions, WinGet
  inventory output, VS Code extension versions, Windows caption, time zone,
  restart status, a Docker-runtime caveat, and whether TCP port 3389 is listening.
* The machine PATH gains the Copilot CLI, Claude Code, and Azurite/npm directories
  when absent; vendor installers can also update PATH.
* The time zone is changed to `GMT Standard Time`.
* WSL and Virtual Machine Platform can require a Windows restart.

The port 3389 check only observes a listening port. It does not enable Remote
Desktop, change a firewall rule, or prove remote connectivity.

> [!NOTE]
> A report is written only after the script reaches its final inventory stage.
> If a later run fails, a report from an earlier run may still exist. Check the
> file timestamp and terminal errors rather than treating its existence as proof
> that the latest run succeeded. Review reports before sharing them.

## After installation

1. Restart Windows if requested, then open a fresh terminal to pick up environment
   changes.
2. Start Docker Desktop manually and complete any first-run prompts. Check its
   backend after startup:

   ```powershell
   docker version
   docker info
   wsl --status
   wsl --list --verbose
   ```

3. Install and configure a WSL distribution separately if your workflow needs one.
4. Authenticate the tools you plan to use:

   ```powershell
   az login
   azd auth login
   gh auth login
   ```

5. Complete Copilot and Claude authentication and any required subscriptions or
   organizational approvals separately.
6. Configure your Git author identity if it is not already set:

   ```powershell
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   ```

`docker --version` in the inventory checks the client, not the daemon. A successful
report does not prove that containers, emulators, cloud logins, database connections,
or AI assistants are operational.

## Rerunning and customization

Rerunning can continue after a restart or a corrected failure, but this is not a
transactional or fully idempotent installer:

* Direct-download installations are skipped by fixed executable-path checks,
  not by compatibility or version comparisons.
* WinGet receives `--no-upgrade`; this is not an update-all script.
* Missing VS Code extensions are installed, and the final configured list is
  checked.
* The GitHub CLI extension install is requested again on every run.
* The time zone is set again, and the final report is replaced only if the run
  reaches report generation.
* Existing software in nonstandard paths may not be detected.

To customize the toolset, edit the script before running it. The main lists are
`$wingetPackages` and `$vscodeExtensions`; other installations and validations are
separate code blocks. Removing a tool also requires updating dependent extension
steps and the final `$software` inventory. Changing only a package list can leave
a later version check calling a tool that is no longer installed.

There is no rollback or uninstall command. Remove software with Windows Settings
or the relevant package manager, and review feature, PATH, and time-zone changes
separately.

## Troubleshooting

| Symptom                                   | Action                                                                                                          |
|-------------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| Administrator requirement fails           | Open an elevated session as the intended desktop user, not `SYSTEM`.                                             |
| 64-bit or Windows-build check fails        | Use 64-bit PowerShell on a supported x64 Windows desktop build; Windows Server is rejected.                       |
| Script execution is blocked                | Inspect the file and follow approved execution-policy guidance; unblocking is not a policy bypass.               |
| WinGet cannot be bootstrapped              | Check PowerShell Gallery access, App Installer/WinGet availability, proxy settings, and organization policy.      |
| Download, signature, or checksum fails     | Stop and inspect the vendor source, network, and package availability. Do not remove integrity checks.           |
| A pinned release or package is unavailable | Check the version or package ID in the source against the upstream publisher; update deliberately before retrying. |
| Installer exceeds ten minutes             | Inspect the installer's state and Windows installation logs before rerunning; do not assume changes rolled back. |
| WinGet requests a restart                  | Save work, restart Windows, and rerun the script as directed.                                                     |
| Extensions appear in the wrong profile     | Check which account ran the elevated script; editor and CLI extensions are account-scoped.                       |
| A command is not found after setup         | Open a new terminal and confirm the expected installation path and machine/user PATH entries.                    |
| .NET 10 or C++ workload validation fails   | Check the corresponding installation; ensure the Desktop development with C++ workload is present, then rerun.   |
| Docker CLI works but containers do not     | Start Docker Desktop; check its backend, WSL state, restart requirements, and hardware or nested virtualization.  |
| No new readiness report appears            | Read the terminal's first failure and check the report timestamp; generation occurs only at the end.             |

The script does not create a dedicated log file. Preserve terminal output when
investigating a failure, and remove sensitive account, machine, or authentication
information before sharing it.

## Development and contributions

The repository currently consists of this README and the installer. There is no
automated test suite or CI configuration.

Before proposing a change:

1. Keep tool IDs, release paths, expected publisher checks, and inventory commands
   consistent.
2. Update this README when the toolset, prerequisites, or side effects change.
3. Parse the script without executing its installation steps:

   ```powershell
   $tokens = $null
   $parseErrors = $null
   [System.Management.Automation.Language.Parser]::ParseFile(
       (Join-Path $PWD 'install-devtools.ps1'),
       [ref]$tokens,
       [ref]$parseErrors
   ) | Out-Null
   if ($parseErrors.Count -gt 0) {
       $parseErrors | Format-List
       throw 'PowerShell parsing failed.'
   }
   git diff --check
   ```

4. Test installation changes on a disposable Windows machine. Record the OS build,
   account context, result, restart requirements, and runtime checks without
   committing generated inventories, credentials, or downloaded installers.
5. Open an issue or pull request in the
   [GitHub repository](https://github.com/siyakhumalo-ms/ps-devtools).

Parsing checks syntax only; it does not establish installer correctness or runtime
compatibility.

## Limitations

* Most releases float to whatever upstream serves when you run the script;
  results are not reproducible from a dependency lockfile.
* Installations are sequential, with no rollback of earlier successful changes.
* Network access, package catalogs, publisher signatures, and installation
  behavior can change independently of this repository.
* The script does not provision cloud resources, sign you in, create projects,
  configure databases, start emulators, or validate the Docker runtime.
* Vendor licenses, subscription terms, and organizational policies apply.
  Installation does not grant product entitlements.

## License

No license file is currently included in this repository. Do not assume an
open-source license applies. Installed third-party tools retain their own licenses.

Documentation prepared with AI assistance and grounded in the repository's script.
