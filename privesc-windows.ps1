$ErrorActionPreference = 'Continue'

param(
    [ValidateSet('stealth','normal','aggressive')]
    [string]$Mode = 'normal',

    [ValidateSet('quiet','normal','verbose')]
    [string]$Verbosity = 'normal',

    [switch]$IntegrateTools,
    [switch]$ValidateSafe
)

function NoiseLevel([string]$n) {
    switch ($n) {
        'stealth' { return 0 }
        'normal' { return 1 }
        'aggressive' { return 2 }
        default { return 1 }
    }
}

function Should-RunNoise([string]$CheckNoise) {
    return (NoiseLevel $CheckNoise) -le (NoiseLevel $Mode)
}

function Log([string]$msg) {
    if ($Verbosity -ne 'quiet') { Write-Host $msg }
}

function VLog([string]$msg) {
    if ($Verbosity -eq 'verbose') { Write-Host $msg }
}

function Run-ToFile {
    param(
        [string]$Path,
        [string]$Command
    )
    try {
        "### CMD: $Command" | Out-File -FilePath $Path -Encoding UTF8
        "### TS: $(Get-Date -Format o)" | Out-File -FilePath $Path -Append -Encoding UTF8
        "" | Out-File -FilePath $Path -Append -Encoding UTF8
        cmd.exe /c $Command | Out-File -FilePath $Path -Append -Encoding UTF8 -Width 4096
    }
    catch {
        "ERROR: $($_.Exception.Message)" | Out-File -FilePath $Path -Append -Encoding UTF8
    }
}

function Add-Finding {
    param(
        [int]$Score,
        [string]$Severity,
        [string]$Confidence,
        [string]$Title,
        [string]$Check,
        [string]$Detail,
        [string]$Ref
    )
    "$Score|$Severity|$Confidence|$Title|$Check|$Detail|$Ref" | Out-File -FilePath $FindingsFile -Append -Encoding UTF8
}

$HostName = $env:COMPUTERNAME
if ([string]::IsNullOrWhiteSpace($HostName)) { $HostName = 'unknown-host' }
$Ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$Root = Join-Path (Get-Location) "privesc\$HostName-$Ts"
$Raw = Join-Path $Root 'raw'
$SummaryDir = Join-Path $Root 'summary'
$null = New-Item -Path $Raw -ItemType Directory -Force
$null = New-Item -Path $SummaryDir -ItemType Directory -Force

$FindingsFile = Join-Path $Root 'findings.tsv'
"" | Out-File -FilePath $FindingsFile -Encoding UTF8

Log "[+] privesc-windows starting"
Log "[+] mode=$Mode verbosity=$Verbosity integrate_tools=$IntegrateTools validate_safe=$ValidateSafe"
Log "[+] output=$Root"

$Checks = @(
    @{ Id='identity'; Noise='stealth'; Category='users'; Cmd='whoami && whoami /groups' },
    @{ Id='privileges'; Noise='stealth'; Category='permissions'; Cmd='whoami /priv' },
    @{ Id='system'; Noise='stealth'; Category='system'; Cmd='systeminfo' },
    @{ Id='network'; Noise='stealth'; Category='network'; Cmd='ipconfig /all & route print & netstat -ano' },
    @{ Id='processes'; Noise='stealth'; Category='processes'; Cmd='tasklist /v' },
    @{ Id='services'; Noise='normal'; Category='services'; Cmd='wmic service get Name,DisplayName,State,StartMode,PathName' },
    @{ Id='scheduled'; Noise='normal'; Category='scheduled'; Cmd='schtasks /query /fo LIST /v' },
    @{ Id='users'; Noise='stealth'; Category='users'; Cmd='net user & net localgroup & net localgroup administrators' },
    @{ Id='credentials'; Noise='normal'; Category='credentials'; Cmd='cmdkey /list' },
    @{ Id='autoruns'; Noise='normal'; Category='filesystem'; Cmd='reg query HKLM\Software\Microsoft\Windows\CurrentVersion\Run & reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run' },
    @{ Id='software'; Noise='normal'; Category='system'; Cmd='wmic product get name,version,vendor' },
    @{ Id='interesting-files'; Noise='aggressive'; Category='filesystem'; Cmd='powershell -NoP -C "Get-ChildItem -Path C:\Users,C:\ProgramData,C:\inetpub -Recurse -ErrorAction SilentlyContinue -Include *.config,*.xml,*.ini,*.txt,web.config,appsettings.json,unattend.xml | Select-Object FullName,Length,LastWriteTime"' }
)

if ($ValidateSafe) {
    $safeIds = @('identity','privileges','system')
    $Checks = $Checks | Where-Object { $safeIds -contains $_.Id }
}

foreach ($check in $Checks) {
    if (-not (Should-RunNoise $check.Noise)) { continue }
    $out = Join-Path $Raw ($check.Id + '.txt')
    VLog "[.] running $($check.Id)"
    Run-ToFile -Path $out -Command $check.Cmd
}

# Correlation / prioritization
$privPath = Join-Path $Raw 'privileges.txt'
if (Test-Path $privPath) {
    $txt = Get-Content $privPath -Raw -ErrorAction SilentlyContinue
    foreach ($p in @('SeImpersonatePrivilege','SeAssignPrimaryTokenPrivilege','SeBackupPrivilege','SeRestorePrivilege')) {
        if ($txt -match $p -and $txt -match 'Enabled') {
            Add-Finding -Score 22 -Severity 'high' -Confidence 'high' -Title "Sensitive privilege enabled: $p" -Check 'privileges' -Detail 'Potential token/service abuse vector' -Ref ''
        }
    }
}

$svcPath = Join-Path $Raw 'services.txt'
if (Test-Path $svcPath) {
    $svc = Get-Content $svcPath -ErrorAction SilentlyContinue
    foreach ($line in $svc) {
        if ($line -match '\.exe' -and $line -match '^\s*[A-Za-z]:\\[^\"]+\s[^\"]+') {
            Add-Finding -Score 13 -Severity 'medium' -Confidence 'low' -Title 'Possible unquoted service path' -Check 'services' -Detail $line.Trim() -Ref ''
        }
        foreach ($lb in @(
            @{n='certutil.exe';u='https://lolbas-project.github.io/lolbas/Binaries/Certutil/'},
            @{n='mshta.exe';u='https://lolbas-project.github.io/lolbas/Binaries/Mshta/'},
            @{n='regsvr32.exe';u='https://lolbas-project.github.io/lolbas/Binaries/Regsvr32/'},
            @{n='rundll32.exe';u='https://lolbas-project.github.io/lolbas/Binaries/Rundll32/'},
            @{n='powershell.exe';u='https://lolbas-project.github.io/lolbas/Binaries/Powershell/'}
        )) {
            if ($line.ToLower().Contains($lb.n)) {
                Add-Finding -Score 10 -Severity 'medium' -Confidence 'medium' -Title "LOLBAS candidate observed: $($lb.n)" -Check 'services' -Detail $line.Trim() -Ref $lb.u
            }
        }
    }
}

$credPath = Join-Path $Raw 'credentials.txt'
if (Test-Path $credPath) {
    $cred = Get-Content $credPath -Raw -ErrorAction SilentlyContinue
    if ($cred -match 'Target:') {
        Add-Finding -Score 18 -Severity 'high' -Confidence 'medium' -Title 'Saved credential entries detected' -Check 'credentials' -Detail 'cmdkey output contains target credentials' -Ref ''
    }
}

$taskPath = Join-Path $Raw 'scheduled.txt'
if (Test-Path $taskPath) {
    $tasks = Get-Content $taskPath -Raw -ErrorAction SilentlyContinue
    if ($tasks -match 'Run As User:\s+SYSTEM') {
        Add-Finding -Score 11 -Severity 'medium' -Confidence 'medium' -Title 'SYSTEM scheduled tasks observed' -Check 'scheduled' -Detail 'Review task action paths/ACLs for write access' -Ref ''
    }
}

if ($IntegrateTools) {
    $toolDir = Join-Path $Root 'tools'
    $null = New-Item -Path $toolDir -ItemType Directory -Force

    $toolCommands = @(
        @{n='winpeas'; c='.\winPEASx64.exe'},
        @{n='seatbelt'; c='.\Seatbelt.exe -group=all'},
        @{n='watson'; c='.\Watson.exe'},
        @{n='powerup'; c='powershell -ep bypass -c ". .\PowerUp.ps1; Invoke-AllChecks"'}
    )

    foreach ($t in $toolCommands) {
        try {
            $out = Join-Path $toolDir ($t.n + '.txt')
            cmd.exe /c $t.c | Out-File -FilePath $out -Encoding UTF8 -Width 4096
            Add-Finding -Score 7 -Severity 'low' -Confidence 'medium' -Title "Tool integration output captured: $($t.n)" -Check 'tool-integration' -Detail 'Executed optional external tool' -Ref ''
        }
        catch {
            # ignore missing tools
        }
    }
}

$SummaryTxt = Join-Path $SummaryDir 'summary.txt'
$SummaryMd = Join-Path $SummaryDir 'summary.md'

$allFindings = @()
if (Test-Path $FindingsFile) {
    $allFindings = Get-Content $FindingsFile | Where-Object { $_ -and $_.Trim() -ne '' }
}

$sorted = $allFindings | Sort-Object {
    try { [int](($_ -split '\|')[0]) } catch { 0 }
} -Descending

"privesc-windows summary" | Out-File -FilePath $SummaryTxt -Encoding UTF8
"timestamp: $(Get-Date -Format o)" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
"host: $HostName" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
"mode: $Mode" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
"verbosity: $Verbosity" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
"integrate_tools: $IntegrateTools" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
"validate_safe: $ValidateSafe" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
"" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
"top findings (score desc):" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8

if ($sorted.Count -gt 0) {
    foreach ($line in $sorted | Select-Object -First 25) {
        $parts = $line -split '\|', 7
        "- [$($parts[0])] $($parts[1])/$($parts[2]) $($parts[3]) ($($parts[4]))" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
        "  detail: $($parts[5])" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
        if ($parts.Count -ge 7 -and $parts[6]) {
            "  ref: $($parts[6])" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
        }
    }
} else {
    "- no prioritized findings" | Out-File -FilePath $SummaryTxt -Append -Encoding UTF8
}

"# Windows PrivEsc Triage Summary" | Out-File -FilePath $SummaryMd -Encoding UTF8
"" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
"- **timestamp**: `$(Get-Date -Format o)`" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
"- **host**: `$HostName`" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
"- **mode**: `$Mode`" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
"- **integrate_tools**: `$IntegrateTools`" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
"" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
"## Top Findings" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
"" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8

if ($sorted.Count -gt 0) {
    foreach ($line in $sorted | Select-Object -First 40) {
        $parts = $line -split '\|', 7
        "### [$($parts[0])] $($parts[3])" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
        "- Severity: `$($parts[1])`" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
        "- Confidence: `$($parts[2])`" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
        "- Check: `$($parts[4])`" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
        "- Detail: `$($parts[5])`" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
        if ($parts.Count -ge 7 -and $parts[6]) {
            "- Ref: $($parts[6])" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
        }
        "" | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
    }
} else {
    "No prioritized findings." | Out-File -FilePath $SummaryMd -Append -Encoding UTF8
}

try {
    Compress-Archive -Path $Root -DestinationPath "$Root.zip" -Force
} catch {
    # ignore if compression unavailable
}

Log "[+] complete"
Log "[+] output dir: $Root"
if (Test-Path "$Root.zip") { Log "[+] archive: $Root.zip" }
Log "[+] summary: $SummaryTxt"
