$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1. Wyszukanie pliku .env w katalogu home.configuration obok repozytorium
$CandidatePaths = @(
    (Join-Path $PSScriptRoot "..\..\Home.Configuration\hostbook.env"),
    (Join-Path $PSScriptRoot "..\..\github\Home.Configuration\hostbook.env")
)

$EnvFile = $CandidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $EnvFile) {
    Write-Error "Nie znaleziono pliku .env w katalogu home.configuration obok projektu."
}

$Config = @{}
Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $parts = $line.Split("=", 2)
        $Config[$parts[0].Trim()] = $parts[1].Trim()
    }
}

$ApiKey   = $Config["FIREBASE_API_KEY"]
$DbUrl    = $Config["FIREBASE_DB_URL"].TrimEnd("/")
$Email    = $Config["FIREBASE_EMAIL"]
$Password = $Config["FIREBASE_PASSWORD"]

# 2. Pobranie wszystkich aktywnych adresów IPv4 (poza 127.0.0.1 i 169.254.x.x)
$LocalIps = @(
    Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" -and -not $_.IPAddress.StartsWith("169.254.") } |
    Select-Object -ExpandProperty IPAddress
)

Write-Output $LocalIps

if ($LocalIps.Count -eq 0) {
    Write-Output "Brak aktywnych adresow IP - pomijam wysylke."
    exit 0
}

$Hostname = $env:COMPUTERNAME
$HostKey  = $Hostname.ToLower() -replace '[.#$\[\]/]', '-'

Write-Output "$apiKey, $DbUrl, $Email, $Password, $Hostname, $HostKey"
# 3. Pobranie tokenu (idToken) z Firebase Auth
$AuthUrl  = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$ApiKey"
$AuthBody = @{
    email             = $Email
    password          = $Password
    returnSecureToken = $true
} | ConvertTo-Json -Compress

$AuthResponse = Invoke-RestMethod -Method Post -Uri $AuthUrl -ContentType "application/json" -Body $AuthBody
$IdToken      = $AuthResponse.idToken

Write-output "OK: Zalogowano do Firebase Auth, idToken: $IdToken"   

# 4. Pobranie czasu dzialania komputera (Uptime) i wyslanie danych (PUT) do Firebase Realtime Database
$BootTime   = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$UptimeSpan = (Get-Date) - $BootTime
$Uptime     = "{0}d {1:D2}h {2:D2}m" -f $UptimeSpan.Days, $UptimeSpan.Hours, $UptimeSpan.Minutes

$ReportUrl = "$DbUrl/hosts/$HostKey.json?auth=$IdToken"
$Payload   = @{
    hostname  = $Hostname
    ips       = $LocalIps
    os        = "windows"
    uptime    = $Uptime
    bootTime  = $BootTime.ToString("yyyy-MM-dd HH:mm:ss")
    updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
} | ConvertTo-Json -Compress

Invoke-RestMethod -Method Put -Uri $ReportUrl -ContentType "application/json; charset=utf-8" -Body $Payload | Out-Null
Write-Output "OK: Zaktualizowano $Hostname ($($LocalIps -join ', '))"