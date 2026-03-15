#!/usr/bin/env bash
# ============================================================
#  diag_linux.sh — Diagnóstico de Infraestrutura Linux
#  Autor: Bruno Alves | github.com/brunoalvestech
#  Versão: 1.0
#  Testado em: Ubuntu 20.04/22.04, Debian 11/12, CentOS 7/8
# ============================================================
# Uso: bash diag_linux.sh
#      bash diag_linux.sh --output /var/reports
# ============================================================

set -euo pipefail

# ── Configuração ──────────────────────────────────────────────
OUTPUT_DIR="$(dirname "$0")/../reports"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
HOSTNAME=$(hostname)
DISK_ALERT=80          # % de uso para gerar alerta
CPU_ALERT=70
RAM_ALERT=80

# Serviços críticos para verificar (adapte ao seu ambiente)
CRITICAL_SERVICES=(
    "ssh"
    "cron"
    "rsyslog"
    "ufw"
    "fail2ban"
    "nginx"
    "docker"
    "zabbix-agent"
)

# ── Cores para output no terminal ────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; RESET='\033[0m'; BOLD='\033[1m'

ok()   { echo -e "${GREEN}[✓]${RESET} $1"; }
warn() { echo -e "${YELLOW}[!]${RESET} $1"; }
fail() { echo -e "${RED}[✗]${RESET} $1"; }
info() { echo -e "${CYAN}[*]${RESET} $1"; }

# ── Parse de args ─────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT_DIR="$2"; shift 2;;
        --help|-h)
            echo "Uso: $0 [--output DIR]"
            exit 0;;
        *) echo "Argumento desconhecido: $1"; exit 1;;
    esac
done

mkdir -p "$OUTPUT_DIR"
REPORT_FILE="$OUTPUT_DIR/diag_${HOSTNAME}_${TIMESTAMP}.html"

echo ""
echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"
echo -e "${BOLD} Diagnóstico de Infraestrutura — $HOSTNAME${RESET}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"
echo ""

# ── Funções de coleta ─────────────────────────────────────────

get_cpu_usage() {
    # Média de uso de CPU nos últimos 1s via /proc/stat
    local cpu1 cpu2
    cpu1=$(grep 'cpu ' /proc/stat)
    sleep 1
    cpu2=$(grep 'cpu ' /proc/stat)
    local idle1 idle2 total1 total2
    idle1=$(echo $cpu1 | awk '{print $5}')
    idle2=$(echo $cpu2 | awk '{print $5}')
    total1=$(echo $cpu1 | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')
    total2=$(echo $cpu2 | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')
    local diff_idle=$(( idle2 - idle1 ))
    local diff_total=$(( total2 - total1 ))
    echo $(( (100 * (diff_total - diff_idle)) / diff_total ))
}

get_ram_info() {
    local total used free pct
    total=$(free -m | awk '/^Mem:/ {print $2}')
    used=$(free -m | awk '/^Mem:/ {print $3}')
    free=$(free -m | awk '/^Mem:/ {print $4}')
    pct=$(( used * 100 / total ))
    echo "$total $used $free $pct"
}

check_service() {
    local svc="$1"
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo "running"
        elif systemctl list-unit-files | grep -q "^${svc}.service"; then
            echo "stopped"
        else
            echo "not_found"
        fi
    else
        if service "$svc" status &>/dev/null 2>&1; then
            echo "running"
        else
            echo "stopped"
        fi
    fi
}

# ── Coleta dos dados ──────────────────────────────────────────
info "Coletando informações do sistema..."

# Sistema
OS_NAME=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || uname -s)
KERNEL=$(uname -r)
UPTIME_RAW=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | xargs)

# CPU
CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
CPU_CORES=$(nproc)
info "Calculando uso de CPU..."
CPU_USAGE=$(get_cpu_usage)

# RAM
read RAM_TOTAL_MB RAM_USED_MB RAM_FREE_MB RAM_PCT <<< $(get_ram_info)
RAM_TOTAL_GB=$(echo "scale=1; $RAM_TOTAL_MB / 1024" | bc)
RAM_USED_GB=$(echo "scale=1; $RAM_USED_MB / 1024" | bc)

# Swap
SWAP_TOTAL=$(free -m | awk '/^Swap:/ {print $2}')
SWAP_USED=$(free -m | awk '/^Swap:/ {print $3}')
SWAP_PCT=0
[[ $SWAP_TOTAL -gt 0 ]] && SWAP_PCT=$(( SWAP_USED * 100 / SWAP_TOTAL ))

# Discos
info "Verificando discos..."
DISK_DATA=""
while IFS= read -r line; do
    MOUNT=$(echo "$line" | awk '{print $6}')
    PCT=$(echo "$line" | awk '{print $5}' | tr -d '%')
    USED=$(echo "$line" | awk '{print $3}')
    AVAIL=$(echo "$line" | awk '{print $4}')
    SIZE=$(echo "$line" | awk '{print $2}')
    FS=$(echo "$line" | awk '{print $1}')
    STATUS="ok"
    [[ $PCT -ge $DISK_ALERT ]] && STATUS="warn"
    [[ $PCT -ge 95 ]]          && STATUS="crit"
    BAR_COLOR=$([ "$STATUS" = "ok" ] && echo "#1D9E75" || echo "#E24B4A")
    DISK_DATA+="<tr><td>$MOUNT</td><td>$FS</td><td>$SIZE</td><td>$AVAIL</td>
        <td><div class='bar-bg'><div class='bar-fill' style='width:${PCT}%;background:${BAR_COLOR}'></div></div>${PCT}%</td>
        <td><span class='badge $STATUS'>$([ "$STATUS" = "ok" ] && echo "OK" || echo "ALERTA")</span></td></tr>"
done < <(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2)

# Serviços
info "Verificando serviços..."
SVC_DATA=""
SVC_FAILED=0
for svc in "${CRITICAL_SERVICES[@]}"; do
    STATUS=$(check_service "$svc")
    case "$STATUS" in
        running)   BADGE="<span class='badge ok'>RODANDO</span>"; STATUS_LABEL="Ativo";;
        stopped)   BADGE="<span class='badge crit'>PARADO</span>"; STATUS_LABEL="Parado"; ((SVC_FAILED++));;
        not_found) BADGE="<span class='badge info'>N/A</span>"; STATUS_LABEL="Não instalado";;
    esac
    SVC_DATA+="<tr><td>$svc</td><td>$BADGE</td><td>$STATUS_LABEL</td></tr>"
done

# Erros de log (últimas 24h)
info "Verificando logs de erros..."
SYSLOG_ERRORS=0
if [[ -f /var/log/syslog ]]; then
    SYSLOG_ERRORS=$(grep -c "error\|ERROR\|CRITICAL\|crit" \
        <(find /var/log -name "syslog" -newer /tmp/_24h_marker 2>/dev/null -exec cat {} \; 2>/dev/null) 2>/dev/null || echo 0)
fi
# Método alternativo via journalctl
if command -v journalctl &>/dev/null; then
    JOURNAL_ERRORS=$(journalctl --since "24 hours ago" -p err --no-pager 2>/dev/null | wc -l || echo 0)
    JOURNAL_CRIT=$(journalctl --since "24 hours ago" -p crit --no-pager 2>/dev/null | wc -l || echo 0)
else
    JOURNAL_ERRORS=0; JOURNAL_CRIT=0
fi

# Conectividade
info "Testando conectividade..."
NET_DATA=""
declare -A NET_HOSTS=(
    ["8.8.8.8"]="Google DNS (internet)"
    ["1.1.1.1"]="Cloudflare DNS"
    ["127.0.0.1"]="Loopback"
)
for ip in "${!NET_HOSTS[@]}"; do
    desc="${NET_HOSTS[$ip]}"
    if ping -c 1 -W 2 "$ip" &>/dev/null; then
        latency=$(ping -c 1 "$ip" | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
        NET_DATA+="<tr><td>$desc</td><td>$ip</td><td>${latency} ms</td><td><span class='badge ok'>OK</span></td></tr>"
        ok "$desc ($ip) — ${latency}ms"
    else
        NET_DATA+="<tr><td>$desc</td><td>$ip</td><td>Timeout</td><td><span class='badge crit'>FALHA</span></td></tr>"
        fail "$desc ($ip) — sem resposta"
    fi
done

# Últimas 5 contas que fizeram login (segurança)
LAST_LOGINS=$(last -n 5 --time-format short 2>/dev/null | head -6 | \
    awk '{printf "<tr><td>%s</td><td>%s</td><td>%s %s</td></tr>\n", $1, $3, $4, $5}' || echo "")

# ── Determina cores dos indicadores ──────────────────────────
cpu_color() { (( $1 >= 90 )) && echo "var(--crit)" || (( $1 >= 70 )) && echo "var(--warn)" || echo "var(--ok)"; }
ram_color() { (( $1 >= 90 )) && echo "var(--crit)" || (( $1 >= 80 )) && echo "var(--warn)" || echo "var(--ok)"; }

CPU_COLOR=$(cpu_color "$CPU_USAGE")
RAM_COLOR=$(ram_color "$RAM_PCT")
LOG_COLOR=$(( JOURNAL_ERRORS >= 20 )) && echo "var(--crit)" || \
            (( JOURNAL_ERRORS >= 5 )) && echo "var(--warn)" || echo "var(--ok)"
LOG_COLOR=$([ "$JOURNAL_ERRORS" -ge 20 ] && echo "var(--crit)" || \
            ([ "$JOURNAL_ERRORS" -ge 5 ] && echo "var(--warn)" || echo "var(--ok)"))

# ── Gera Relatório HTML ───────────────────────────────────────
info "Gerando relatório HTML..."

cat > "$REPORT_FILE" <<HTML
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Diagnóstico — ${HOSTNAME} — ${TIMESTAMP}</title>
<style>
  :root { --ok:#1D9E75; --warn:#BA7517; --crit:#E24B4A; --bg:#f8f7f4; --card:#fff; --border:#e2e0d8; --text:#2c2c2a; --muted:#5f5e5a; }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; background:var(--bg); color:var(--text); padding:32px 24px; max-width:960px; margin:0 auto; }
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
</style>
</head>
<body>

<h1>📋 Diagnóstico de Infraestrutura</h1>
<p class="sub">Servidor: <strong>${HOSTNAME}</strong> &nbsp;|&nbsp; OS: ${OS_NAME} &nbsp;|&nbsp; Kernel: ${KERNEL} &nbsp;|&nbsp; Uptime: ${UPTIME_RAW} &nbsp;|&nbsp; Gerado: ${TIMESTAMP}</p>

<div class="grid">
  <div class="metric">
    <div class="label">CPU</div>
    <div class="value" style="color:${CPU_COLOR}">${CPU_USAGE}%</div>
    <div class="detail">${CPU_CORES} núcleos &nbsp;|&nbsp; Load: ${LOAD_AVG}</div>
  </div>
  <div class="metric">
    <div class="label">Memória RAM</div>
    <div class="value" style="color:${RAM_COLOR}">${RAM_PCT}%</div>
    <div class="detail">${RAM_USED_GB} GB usados de ${RAM_TOTAL_GB} GB</div>
  </div>
  <div class="metric">
    <div class="label">Erros no Journal (24h)</div>
    <div class="value" style="color:${LOG_COLOR}">${JOURNAL_ERRORS}</div>
    <div class="detail">${JOURNAL_CRIT} críticos &nbsp;|&nbsp; Swap: ${SWAP_PCT}% usado</div>
  </div>
  <div class="metric">
    <div class="label">Serviços com problema</div>
    <div class="value" style="color:$([ "$SVC_FAILED" -gt 0 ] && echo "var(--crit)" || echo "var(--ok)")">${SVC_FAILED}</div>
    <div class="detail">de ${#CRITICAL_SERVICES[@]} verificados</div>
  </div>
</div>

<div class="section">
  <h2>💾 Discos</h2>
  <table>
    <tr><th>Ponto de Montagem</th><th>Filesystem</th><th>Total</th><th>Livre</th><th>Uso</th><th>Status</th></tr>
    ${DISK_DATA}
  </table>
</div>

<div class="section">
  <h2>⚙️ Serviços Críticos</h2>
  <table>
    <tr><th>Serviço</th><th>Status</th><th>Estado</th></tr>
    ${SVC_DATA}
  </table>
</div>

<div class="section">
  <h2>🌐 Conectividade de Rede</h2>
  <table>
    <tr><th>Destino</th><th>IP</th><th>Latência</th><th>Status</th></tr>
    ${NET_DATA}
  </table>
</div>

<div class="section">
  <h2>🔐 Últimos Logins</h2>
  <table>
    <tr><th>Usuário</th><th>IP/Terminal</th><th>Data/Hora</th></tr>
    ${LAST_LOGINS}
  </table>
</div>

<footer>Gerado por diag_linux.sh &nbsp;·&nbsp; github.com/brunoalvestech</footer>
</body>
</html>
HTML

echo ""
ok "Relatório gerado: $REPORT_FILE"
echo ""

# Resumo no terminal
echo -e "${BOLD}Resumo:${RESET}"
(( CPU_USAGE >= CPU_ALERT ))  && warn "CPU em ${CPU_USAGE}%" || ok "CPU: ${CPU_USAGE}%"
(( RAM_PCT   >= RAM_ALERT ))  && warn "RAM em ${RAM_PCT}%"   || ok "RAM: ${RAM_PCT}%"
(( SVC_FAILED > 0 ))          && fail "$SVC_FAILED serviço(s) parado(s)" || ok "Todos os serviços rodando"
(( JOURNAL_ERRORS >= 5 ))     && warn "$JOURNAL_ERRORS erros no journal (24h)" || ok "Logs sem erros críticos"
echo ""
