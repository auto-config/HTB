$ErrorActionPreference = 'Continue'

function Write-Section {
    param([string]$Name)
    Write-Host "`n[+] $Name"
}

function Run-ToFile {
    param(
        [string]$OutFile,
        [scriptblock]$Script
    )
    try {
        "### TS: $(Get-Date -Format o)" | Out-File -FilePath $OutFile -Encoding UTF8
        "" | Out-File -FilePath $OutFile -Append -Encoding UTF8
        & $Script | Out-File -FilePath $OutFile -Append -Encoding UTF8 -Width 4096
    }
    catch {
        "[!] Error: $($_.Exception.Message)" | Out-File -FilePath $OutFile -Append -Encoding UTF8
    }
}

$HostName = $env:COMPUTERNAME
if ([string]::IsNullOrWhiteSpace($HostName)) { $HostName = 'unknown-host' }
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Root = Join-Path (Get-Location) ("{0}-{1}-loot" -f $HostName, $Timestamp)

$SystemDir = Join-Path $Root 'system'
$NetworkDir = Join-Path $Root 'network'
$UsersDir = Join-Path $Root 'users'
$ProcessesDir = Join-Path $Root 'processes'
$ServicesDir = Join-Path $Root 'services'
$ScheduledDir = Join-Path $Root 'scheduled'
$FilesDir = Join-Path $Root 'files'
$PermsDir = Join-Path $Root 'permissions'
$SummaryDir = Join-Path $Root 'summary'

$Dirs = @($SystemDir,$NetworkDir,$UsersDir,$ProcessesDir,$ServicesDir,$ScheduledDir,$FilesDir,$PermsDir,$SummaryDir)
foreach ($d in $Dirs) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

$Summary = Join-Path $SummaryDir 'summary.txt'
"loot-windows summary" | Out-File -FilePath $Summary -Encoding UTF8
"timestamp: $(Get-Date -Format o)" | Out-File -FilePath $Summary -Append -Encoding UTF8
"host: $HostName" | Out-File -FilePath $Summary -Append -Encoding UTF8
"user: $env:USERNAME" | Out-File -FilePath $Summary -Append -Encoding UTF8
"root_dir: $Root" | Out-File -FilePath $Summary -Append -Encoding UTF8

Write-Section 'System'
Run-ToFile (Join-Path $SystemDir 'whoami.txt') { whoami }
Run-ToFile (Join-Path $SystemDir 'whoami-all.txt') { whoami /all }
Run-ToFile (Join-Path $SystemDir 'hostname.txt') { hostname }
Run-ToFile (Join-Path $SystemDir 'os-info.txt') { Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture,CSName }
Run-ToFile (Join-Path $SystemDir 'computer-system.txt') { Get-CimInstance Win32_ComputerSystem | Select-Object Domain,Manufacturer,Model,TotalPhysicalMemory }
Run-ToFile (Join-Path $SystemDir 'env.txt') { Get-ChildItem Env: }

Write-Section 'Users and Groups'
Run-ToFile (Join-Path $UsersDir 'net-user.txt') { net user }
Run-ToFile (Join-Path $UsersDir 'net-localgroup.txt') { net localgroup }
Run-ToFile (Join-Path $UsersDir 'local-users.txt') { Get-LocalUser }
Run-ToFile (Join-Path $UsersDir 'local-groups.txt') { Get-LocalGroup }
Run-ToFile (Join-Path $UsersDir 'local-admin-members.txt') { Get-LocalGroupMember -Group 'Administrators' }

Write-Section 'Network'
Run-ToFile (Join-Path $NetworkDir 'ipconfig-all.txt') { ipconfig /all }
Run-ToFile (Join-Path $NetworkDir 'routes.txt') { route print }
Run-ToFile (Join-Path $NetworkDir 'arp.txt') { arp -a }
Run-ToFile (Join-Path $NetworkDir 'tcp-connections.txt') { Get-NetTCPConnection }
Run-ToFile (Join-Path $NetworkDir 'udp-endpoints.txt') { Get-NetUDPEndpoint }
Run-ToFile (Join-Path $NetworkDir 'listeners-netstat.txt') { netstat -ano }

Write-Section 'Processes and Services'
Run-ToFile (Join-Path $ProcessesDir 'processes.txt') { Get-Process | Sort-Object ProcessName }
Run-ToFile (Join-Path $ProcessesDir 'wmic-process.txt') { wmic process get Name,ProcessId,ExecutablePath,CommandLine }
Run-ToFile (Join-Path $ServicesDir 'services.txt') { Get-Service | Sort-Object Status,Name }
Run-ToFile (Join-Path $ServicesDir 'wmic-services.txt') { wmic service get Name,DisplayName,State,StartMode,PathName }

Write-Section 'Scheduled Tasks'
Run-ToFile (Join-Path $ScheduledDir 'schtasks.txt') { schtasks /query /fo LIST /v }
Run-ToFile (Join-Path $ScheduledDir 'scheduledtasks-ps.txt') { Get-ScheduledTask | Select-Object TaskName,TaskPath,State,Author }

Write-Section 'Permissions and Writable Locations'
Run-ToFile (Join-Path $PermsDir 'writable-common-paths.txt') {
    $candidates = @('C:\\Temp','C:\\Windows\\Temp','C:\\Users\\Public','C:\\ProgramData')
    foreach ($p in $candidates) {
        if (Test-Path $p) {
            try {
                $testFile = Join-Path $p ("writetest_{0}.tmp" -f ([guid]::NewGuid().ToString()))
                New-Item -Path $testFile -ItemType File -Force | Out-Null
                Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue
                "WRITABLE: $p"
            } catch {
                "NOT WRITABLE: $p"
            }
        }
    }
}

Write-Section 'Interesting Files and Web Roots'
Run-ToFile (Join-Path $FilesDir 'web-roots.txt') {
    $roots = @('C:\\inetpub\\wwwroot','C:\\xampp\\htdocs','C:\\web','C:\\Sites')
    foreach ($r in $roots) {
        if (Test-Path $r) { Get-ChildItem -Path $r -Recurse -ErrorAction SilentlyContinue }
    }
}
Run-ToFile (Join-Path $FilesDir 'interesting-files.txt') {
    $paths = @('C:\\Users','C:\\ProgramData','C:\\inetpub','C:\\xampp')
    $patterns = @('*.config','*.xml','*.ini','*.txt','*.ps1','*.bat','*.kdbx','*.pfx','*.rdp','*pass*','*secret*','*token*','web.config','appsettings.json','unattend.xml')
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue -Include $patterns
        }
    }
}

Write-Section 'PowerShell History Inventory (metadata only)'
Run-ToFile (Join-Path $FilesDir 'ps-history-inventory.txt') {
    Get-ChildItem -Path 'C:\\Users' -Recurse -ErrorAction SilentlyContinue -Filter 'ConsoleHost_history.txt' |
      Select-Object FullName,Length,LastWriteTime
}

Write-Section 'Registry Autoruns (read-only)'
Run-ToFile (Join-Path $FilesDir 'autoruns-hklm-run.txt') { reg query "HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" }
Run-ToFile (Join-Path $FilesDir 'autoruns-hklm-runonce.txt') { reg query "HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce" }
Run-ToFile (Join-Path $FilesDir 'autoruns-hkcu-run.txt') { reg query "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" }
Run-ToFile (Join-Path $FilesDir 'autoruns-hkcu-runonce.txt') { reg query "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce" }

Write-Section 'Installed Software'
Run-ToFile (Join-Path $SystemDir 'installed-software-uninstall-keys.txt') {
    $keys = @(
      'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
      'HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
      'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'
    )
    foreach ($k in $keys) {
        Get-ItemProperty $k -ErrorAction SilentlyContinue |
          Select-Object DisplayName,DisplayVersion,Publisher,InstallDate
    }
}

Write-Section 'Summary'
$Collected = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue
"files_collected: $($Collected.Count)" | Out-File -FilePath $Summary -Append -Encoding UTF8
"" | Out-File -FilePath $Summary -Append -Encoding UTF8
"important_paths:" | Out-File -FilePath $Summary -Append -Encoding UTF8
"- $($UsersDir)\\local-admin-members.txt" | Out-File -FilePath $Summary -Append -Encoding UTF8
"- $($NetworkDir)\\listeners-netstat.txt" | Out-File -FilePath $Summary -Append -Encoding UTF8
"- $($ProcessesDir)\\processes.txt" | Out-File -FilePath $Summary -Append -Encoding UTF8
"- $($FilesDir)\\interesting-files.txt" | Out-File -FilePath $Summary -Append -Encoding UTF8
"" | Out-File -FilePath $Summary -Append -Encoding UTF8
"generated_files:" | Out-File -FilePath $Summary -Append -Encoding UTF8
$Collected | ForEach-Object { "- $($_.FullName.Replace($Root + '\\',''))" } | Out-File -FilePath $Summary -Append -Encoding UTF8

Write-Section 'Archiving'
$ZipPath = "$Root.zip"
try {
    Compress-Archive -Path $Root -DestinationPath $ZipPath -Force
    Write-Host "Archive: $ZipPath"
} catch {
    Write-Host "[!] Compress-Archive failed: $($_.Exception.Message)"
}

Write-Section 'Complete'
Write-Host "Loot directory: $Root"
Write-Host "Summary: $Summary"
