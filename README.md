# infra-diagnostic

Scripts de diagnóstico para ambientes Windows Server e Linux. Geram um relatório HTML com o estado atual da infraestrutura — CPU, memória, disco, serviços, Active Directory e conectividade.

Escrevi isso porque no dia a dia de suporte N2/N3 perco tempo abrindo Gerenciador de Tarefas, Visualizador de Eventos e AD Users um por um. Agora rodo um script e tenho tudo num lugar só.

---

## Como usar

**Windows Server**

```powershell
# precisa rodar como Administrador
.\scripts\diag_windows.ps1

# se quiser salvar o relatório em outro lugar
.\scripts\diag_windows.ps1 -OutputPath "C:\Relatorios"

# em máquinas sem AD
.\scripts\diag_windows.ps1 -SkipAD
```

Para as verificações de Active Directory, o módulo RSAT precisa estar instalado.

**Linux**

```bash
chmod +x scripts/diag_linux.sh
bash scripts/diag_linux.sh

# caminho personalizado para o relatório
bash scripts/diag_linux.sh --output /var/reports
```

Testado em Ubuntu 20.04/22.04, Debian 11/12 e CentOS 7/8.

---

## O que é verificado

No Windows: sistema operacional, uptime, uso de CPU e RAM, espaço em disco por drive, status dos serviços críticos (AD DS, DNS, DHCP, Netlogon, WinRM), saúde do Active Directory (SYSVOL, replicação, contas bloqueadas) e erros no Event Log das últimas 24h.

No Linux: mesmas métricas de sistema, todos os filesystems montados, serviços via systemd, erros no journalctl das últimas 24h e últimos logins.

---

## Personalização

Os serviços monitorados ficam num array no início de cada script. É só adicionar ou remover conforme o ambiente:

```powershell
# diag_windows.ps1
$CriticalServices = @("NTDS", "DNS", "DHCPServer", "SeuServicoAqui")
```

```bash
# diag_linux.sh
CRITICAL_SERVICES=("ssh" "nginx" "docker" "seu-servico")
```

Os limites de alerta também ficam no início do script e são fáceis de ajustar.

---

## Próximos passos

- Agendamento via Task Scheduler e cron com envio do relatório por e-mail
- Alerta no Telegram quando algum status for crítico
- Suporte a múltiplos hosts remotos

---

## Ambiente de desenvolvimento

PowerShell 5.1+ e Bash 4+. Sem dependências externas.

---

Bruno Alves — [linkedin.com/in/brunoalvestech](https://linkedin.com/in/brunoalvestech)
