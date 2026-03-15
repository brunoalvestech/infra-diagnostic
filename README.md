# infra-diagnostic

Scripts de diagnóstico de infraestrutura para ambientes Windows Server e Linux — geram relatórios HTML com análise de CPU, memória, disco, serviços, Active Directory e conectividade de rede.

Desenvolvido com base em experiência real de suporte N2/N3 em ambientes com Windows Server, Active Directory, Proxmox e pfSense.

---

## O que os scripts verificam

### Windows (`diag_windows.ps1`)
| Categoria | Detalhes |
|-----------|----------|
| Sistema | OS, build, uptime, CPU, RAM |
| Disco | Uso por drive com alerta configurável |
| Serviços | AD DS, DNS, DHCP, Netlogon, WinRM e outros |
| Active Directory | SYSVOL, NETLOGON, replicação, contas bloqueadas |
| Logs | Erros críticos no Event Log (últimas 24h) |
| Rede | Ping com latência para destinos configuráveis |

### Linux (`diag_linux.sh`)
| Categoria | Detalhes |
|-----------|----------|
| Sistema | OS, kernel, uptime, load average |
| CPU/RAM/Swap | Uso em tempo real via `/proc/stat` e `free` |
| Disco | Todos os filesystems montados com barra de uso |
| Serviços | systemd — qualquer serviço configurável |
| Logs | Erros e críticos via `journalctl` (últimas 24h) |
| Rede | Ping com latência para múltiplos destinos |
| Segurança | Últimos logins no sistema |

---

## Como usar

### Windows Server

```powershell
# Execução básica (salva em ./reports/)
.\scripts\diag_windows.ps1

# Com caminho personalizado para o relatório
.\scripts\diag_windows.ps1 -OutputPath "C:\Relatorios"

# Sem verificações de Active Directory (workstations ou servidores sem AD)
.\scripts\diag_windows.ps1 -SkipAD
```

> **Permissões:** Execute como Administrador. Para as verificações de AD, é necessário ter o módulo RSAT instalado.

### Linux

```bash
# Dar permissão de execução
chmod +x scripts/diag_linux.sh

# Execução básica
bash scripts/diag_linux.sh

# Com caminho personalizado para o relatório
bash scripts/diag_linux.sh --output /var/reports
```

> Testado em Ubuntu 20.04/22.04, Debian 11/12 e CentOS 7/8. Requer: `bash`, `ping`, `df`, `free`, `journalctl`.

---

## Estrutura do repositório

```
infra-diagnostic/
├── scripts/
│   ├── diag_windows.ps1    # Script para Windows Server
│   └── diag_linux.sh       # Script para Linux
├── reports/                # Relatórios gerados (ignorado pelo Git)
├── docs/
│   └── exemplo-relatorio.png
└── README.md
```

---

## Exemplo de relatório

O relatório HTML gerado inclui:
- Cards com métricas principais (CPU, RAM, erros de log)
- Barras de uso visual para cada disco
- Badges coloridos por status (verde / amarelo / vermelho)
- Tabelas de serviços, conectividade e AD

---

## Personalização

### Adicionar serviços para monitorar (Windows)

Edite o array `$CriticalServices` em `diag_windows.ps1`:

```powershell
$CriticalServices = @(
    "NTDS",
    "DNS",
    "DHCPServer",
    "SeuServicoAqui"   # ← adicione aqui
)
```

### Alterar limites de alerta (Linux)

Edite as variáveis no início de `diag_linux.sh`:

```bash
DISK_ALERT=80   # % de uso do disco para gerar alerta
CPU_ALERT=70
RAM_ALERT=80
```

---

## Roadmap

- [x] Diagnóstico Windows Server com relatório HTML
- [x] Diagnóstico Linux com relatório HTML
- [ ] Agendamento via Task Scheduler / cron com envio por e-mail
- [ ] Alerta automático no Telegram quando status for CRÍTICO
- [ ] Suporte a múltiplos hosts remotos (via WinRM / SSH)
- [ ] Integração com Zabbix para disparar script via trigger

---

## Tecnologias

![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)
![Windows Server](https://img.shields.io/badge/Windows_Server-0078D6?style=flat&logo=windows&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)

---

## Autor

**Bruno Alves** — Analista de Suporte N2 | Infraestrutura e Redes

[![LinkedIn](https://img.shields.io/badge/LinkedIn-brunoalvestech-0A66C2?style=flat&logo=linkedin)](https://linkedin.com/in/brunoalvestech)
[![GitHub](https://img.shields.io/badge/GitHub-brunoalvestech-181717?style=flat&logo=github)](https://github.com/brunoalvestech)
