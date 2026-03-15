# ============================================================
#  diag_windows.ps1 — Diagnóstico de Infraestrutura Windows
#  Autor: Bruno Alves | github.com/brunoalvestech
#  Versão: 1.0
#  Testado em: Windows Server 2016 / 2019 / 2022
# ============================================================
# Uso: .\diag_windows.ps1
#      .\diag_windows.ps1 -OutputPath "C:\Relatorios"
#      .\diag_windows.ps1 -SkipAD  (pula checks de AD, útil em workstations)
# ============================================================

param(
    [string]$OutputPath = "$PSScriptRoot\..\reports",
    [switch]$SkipAD
)

# ── Configuracao ──────────────────────────────────────────────
$ErrorActionPreference = "SilentlyContinue"
$Timestamp   = Get-Date -Format "yyyy-MM-dd_HH-mm"
$Hostname    = $env:COMPUTERNAME
$ReportFile  = "$OutputPath\diag_${Hostname}_${Timestamp}.html"

# Servicos críticos para monitorar (adicione os do seu ambiente)
$CriticalServices = @(
    "W32Time",       # Sincronizacao de tempo
    "NTDS",          # Active Directory Domain Services
    "DNS",           # Servidor DNS
    "DHCPServer",    # Servidor DHCP
    "LanmanServer",  # File/Print sharing
    "Netlogon",      # Logon de domínio
    "WinRM",         # Gerenciamento remoto
    "EventLog"       # Log de eventos
)

# Discos com alerta acima deste % de uso
$DiskAlertThreshold = 80

# ── Funções ───────────────────────────────────────────────────
function Get-StatusBadge {
    param([string]$Status)
    switch ($Status) {
        "OK"      { return "<span class='badge ok'>OK</span>" }
        "ALERTA"  { return "<span class='badge warn'>ALERTA</span>" }
        "CRITICO" { return "<span class='badge crit'>CRÍTICO</span>" }
        default   { return "<span class='badge info'>$Status</span>" }
    }
}

function Test-ADHealth {
    $results = @()
    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        # Verifica SYSVOL e NETLOGON
        $sysvol  = Test-Path "\\$Hostname\SYSVOL"
        $netlogon = Test-Path "\\$Hostname\NETLOGON"
        $results += [PSCustomObject]@{
            Verificacao = "SYSVOL compartilhado"
            Status      = if ($sysvol) { "OK" } else { "CRITICO" }
            Detalhe     = if ($sysvol) { "Acessível" } else { "SYSVOL inacessível!" }
        }
        $results += [PSCustomObject]@{
            Verificacao = "NETLOGON compartilhado"
            Status      = if ($netlogon) { "OK" } else { "CRITICO" }
            Detalhe     = if ($netlogon) { "Acessível" } else { "NETLOGON inacessível!" }
        }

        # Última replicacao do AD
        $replSummary = (repadmin /replsummary 2>&1) -join " "
        $hasErrors = $replSummary -match "error|fail"
        $results += [PSCustomObject]@{
            Verificacao = "Replicacao AD (repadmin)"
            Status      = if ($hasErrors) { "ALERTA" } else { "OK" }
            Detalhe     = if ($hasErrors) { "Possíveis erros de replicacao — execute repadmin /showrepl" } else { "Sem erros detectados" }
        }

        # Contas bloqueadas nas ultimas 24h
        $cutoff  = (Get-Date).AddHours(-24)
        $locked  = (Search-ADAccount -LockedOut -UsersOnly | Where-Object {$_.LastLogonDate -gt $cutoff}).Count
        $results += [PSCustomObject]@{
            Verificacao = "Contas bloqueadas (24h)"
            Status      = if ($locked -gt 5) { "ALERTA" } else { "OK" }
            Detalhe     = "$locked conta(s) bloqueada(s) — verifique política de lockout"
        }

        # Total de usuários habilitados
        $totalUsers = (Get-ADUser -Filter {Enabled -eq $true}).Count
        $results += [PSCustomObject]@{
            Verificacao = "Usuários ativos no AD"
            Status      = "OK"
            Detalhe     = "$totalUsers usuários habilitados"
        }
    }
    catch {
        $results += [PSCustomObject]@{
            Verificacao = "Modulo ActiveDirectory"
            Status      = "ALERTA"
            Detalhe     = "Modulo RSAT não instalado ou sem permissão de consulta"
        }
    }
    return $results
}

# ── Coleta de dados ───────────────────────────────────────────
Write-Host "`n[*] Iniciando diagnóstico em $Hostname..." -ForegroundColor Cyan

# Sistema Operacional
$OS      = Get-CimInstance Win32_OperatingSystem
$UptimeDays = ([datetime]::Now - $OS.LastBootUpTime).Days
$UptimeHrs  = ([datetime]::Now - $OS.LastBootUpTime).Hours

# CPU
$CPU      = Get-CimInstance Win32_Processor | Select-Object -First 1
$CPULoad  = (Get-CimInstance Win32_Processor).LoadPercentage

# Memória
$TotalRAM = [math]::Round($OS.TotalVisibleMemorySize / 1MB, 1)
$FreeRAM  = [math]::Round($OS.FreePhysicalMemory / 1MB, 1)
$UsedRAM  = [math]::Round($TotalRAM - $FreeRAM, 1)
$RAMPct   = [math]::Round(($UsedRAM / $TotalRAM) * 100)

# Discos
$Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $pct = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100)
    [PSCustomObject]@{
        Drive     = $_.DeviceID
        TotalGB   = [math]::Round($_.Size / 1GB, 1)
        FreeGB    = [math]::Round($_.FreeSpace / 1GB, 1)
        UsoPct    = $pct
        Status    = if ($pct -ge $DiskAlertThreshold) { "ALERTA" } else { "OK" }
    }
}

# Servicos
$ServiceResults = $CriticalServices | ForEach-Object {
    $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Servico = if ($svc) { $svc.DisplayName } else { $_ }
        Nome    = $_
        Status  = if (!$svc) { "N/A" } elseif ($svc.Status -eq "Running") { "OK" } else { "CRITICO" }
        Estado  = if ($svc) { $svc.Status } else { "Não instalado" }
    }
}

# Eventos de Erro (ultimas 24h — apenas críticos)
$Since     = (Get-Date).AddHours(-24)
$SysErrors = (Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=$Since} -ErrorAction SilentlyContinue).Count
$AppErrors = (Get-WinEvent -FilterHashtable @{LogName='Application';Level=1,2;StartTime=$Since} -ErrorAction SilentlyContinue).Count

# Conectividade básica
$NetworkTests = @(
    @{ Host="8.8.8.8";     Desc="Google DNS (internet)" },
    @{ Host="1.1.1.1";     Desc="Cloudflare DNS" },
    @{ Host=$Hostname;     Desc="Loopback local" }
) | ForEach-Object {
    $ping = Test-Connection -ComputerName $_.Host -Count 1 -Quiet
    [PSCustomObject]@{
        Destino = $_.Desc
        IP      = $_.Host
        Status  = if ($ping) { "OK" } else { "CRITICO" }
        Latência = if ($ping) {
            "$((Test-Connection $_.Host -Count 1).ResponseTime) ms"
        } else { "Timeout" }
    }
}

# Active Directory (opcional)
$ADResults = @()
if (-not $SkipAD) {
    Write-Host "[*] Verificando Active Directory..." -ForegroundColor Cyan
    $ADResults = Test-ADHealth
}

# ── Gera Relatório HTML ───────────────────────────────────────
Write-Host "[*] Gerando relatório HTML..." -ForegroundColor Cyan
if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath | Out-Null }

$RAMStatus   = if ($RAMPct -ge 90) { "CRITICO" } elseif ($RAMPct -ge 75) { "ALERTA" } else { "OK" }
$CPUStatus   = if ($CPULoad -ge 90) { "CRITICO" } elseif ($CPULoad -ge 70) { "ALERTA" } else { "OK" }
$EventStatus = if ($SysErrors -ge 20) { "CRITICO" } elseif ($SysErrors -ge 5) { "ALERTA" } else { "OK" }

# Monta tabela de serviços
$SvcRows = ($ServiceResults | ForEach-Object {
    "<tr><td>$($_.Servico)</td><td>$(Get-StatusBadge $_.Status)</td><td>$($_.Estado)</td></tr>"
}) -join "`n"

# Monta tabela de discos
$DiskRows = ($Disks | ForEach-Object {
    "<tr><td>$($_.Drive)</td><td>$($_.TotalGB) GB</td><td>$($_.FreeGB) GB</td>
     <td><div class='bar-bg'><div class='bar-fill' style='width:$($_.UsoPct)%;background:$(if($_.UsoPct -ge 80){"#E24B4A"}else{"#1D9E75"})'></div></div>$($_.UsoPct)%</td>
     <td>$(Get-StatusBadge $_.Status)</td></tr>"
}) -join "`n"

# Monta tabela de rede
$NetRows = ($NetworkTests | ForEach-Object {
    "<tr><td>$($_.Destino)</td><td>$($_.IP)</td><td>$($_.Latência)</td><td>$(Get-StatusBadge $_.Status)</td></tr>"
}) -join "`n"

# Monta tabela AD
$ADRows = ""
if ($ADResults.Count -gt 0) {
    $ADRows = ($ADResults | ForEach-Object {
        "<tr><td>$($_.Verificacao)</td><td>$(Get-StatusBadge $_.Status)</td><td>$($_.Detalhe)</td></tr>"
    }) -join "`n"
}

$HTML = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Diagnóstico — $Hostname — $Timestamp</title>
<style>
  :root { --ok:#1D9E75; --warn:#BA7517; --crit:#E24B4A; --bg:#f8f7f4; --card:#fff; --border:#e2e0d8; --text:#2c2c2a; --muted:#5f5e5a; }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; background:var(--bg); color:var(--text); padding:32px 24px; }
  h1 { font-size:22px; font-weight:600; margin-bottom:4px; }
  .sub { color:var(--muted); font-size:13px; margin-bottom:28px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:14px; margin-bottom:28px; }
  .metric { background:var(--card); border:1px solid var(--border); border-radius:10px; padding:16px 18px; }
  .metric .label { font-size:12px; color:var(--muted); margin-bottom:6px; }
  .metric .value { font-size:26px; font-weight:600; }
  .metric .detail { font-size:12px; color:var(--muted); margin-top:4px; }
  .section { background:var(--card); border:1px solid var(--border); border-radius:10px; padding:20px; margin-bottom:20px; }
  .section h2 { font-size:15px; font-weight:600; margin-bottom:14px; padding-bottom:10px; border-bottom:1px solid var(--border); }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th { text-align:left; padding:8px 10px; color:var(--muted); font-weight:500; font-size:12px; border-bottom:1px solid var(--border); }
  td { padding:9px 10px; border-bottom:1px solid var(--border); }
  tr:last-child td { border-bottom:none; }
  .badge { display:inline-block; padding:3px 10px; border-radius:20px; font-size:11px; font-weight:600; }
  .badge.ok   { background:#E1F5EE; color:#085041; }
  .badge.warn { background:#FAEEDA; color:#633806; }
  .badge.crit { background:#FCEBEB; color:#501313; }
  .badge.info { background:#E6F1FB; color:#042C53; }
  .bar-bg { display:inline-block; width:100px; height:8px; background:#f0efe8; border-radius:4px; vertical-align:middle; margin-right:6px; }
  .bar-fill { height:8px; border-radius:4px; }
  footer { text-align:center; color:var(--muted); font-size:12px; margin-top:32px; }
  @media (max-width:600px) { body { padding:16px; } }
</style>
</head>
<body>

<h1>📋 Diagnóstico de Infraestrutura</h1>
<p class="sub">Servidor: <strong>$Hostname</strong> &nbsp;|&nbsp; Gerado em: $Timestamp &nbsp;|&nbsp; Uptime: ${UptimeDays}d ${UptimeHrs}h</p>

<div class="grid">
  <div class="metric">
    <div class="label">CPU</div>
    <div class="value" style="color:$(if($CPULoad -ge 90){"var(--crit)"}elseif($CPULoad -ge 70){"var(--warn)"}else{"var(--ok)"})">$CPULoad%</div>
    <div class="detail">$($CPU.Name)</div>
  </div>
  <div class="metric">
    <div class="label">Memória RAM</div>
    <div class="value" style="color:$(if($RAMPct -ge 90){"var(--crit)"}elseif($RAMPct -ge 75){"var(--warn)"}else{"var(--ok)"})">$RAMPct%</div>
    <div class="detail">$UsedRAM GB usados de $TotalRAM GB</div>
  </div>
  <div class="metric">
    <div class="label">Erros no Sistema (24h)</div>
    <div class="value" style="color:$(if($SysErrors -ge 20){"var(--crit)"}elseif($SysErrors -ge 5){"var(--warn)"}else{"var(--ok)"})">$SysErrors</div>
    <div class="detail">$AppErrors erros na Application Log</div>
  </div>
  <div class="metric">
    <div class="label">SO</div>
    <div class="value" style="font-size:16px;padding-top:4px">$($OS.Caption)</div>
    <div class="detail">Build $($OS.BuildNumber)</div>
  </div>
</div>

<div class="section">
  <h2>💾 Discos</h2>
  <table>
    <tr><th>Drive</th><th>Total</th><th>Livre</th><th>Uso</th><th>Status</th></tr>
    $DiskRows
  </table>
</div>

<div class="section">
  <h2>⚙️ Servicos Críticos</h2>
  <table>
    <tr><th>Servico</th><th>Status</th><th>Estado</th></tr>
    $SvcRows
  </table>
</div>

<div class="section">
  <h2>🌐 Conectividade de Rede</h2>
  <table>
    <tr><th>Destino</th><th>IP</th><th>Latência</th><th>Status</th></tr>
    $NetRows
  </table>
</div>

$(if ($ADRows -ne "") {
"<div class='section'>
  <h2>🏢 Active Directory</h2>
  <table>
    <tr><th>Verificacao</th><th>Status</th><th>Detalhe</th></tr>
    $ADRows
  </table>
</div>"
})

<footer>Gerado por diag_windows.ps1 &nbsp;·&nbsp; github.com/brunoalvestech</footer>
</body>
</html>
"@

$HTML | Out-File -FilePath $ReportFile -Encoding UTF8
Write-Host "`n[✓] Relatório salvo em: $ReportFile" -ForegroundColor Green

# Abre no navegador automaticamente
Start-Process $ReportFile
