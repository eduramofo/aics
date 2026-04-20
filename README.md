# AICS — Automatic Internet Connection Sharing Service

Serviço automático para Windows que configura e mantém o compartilhamento de internet (ICS) ativo de forma persistente.

Funciona como um **roteador virtual**, compartilhando a conexão principal com uma interface secundária (ex: Ethernet, impressora, rede local).

---

## Instalação

1. Coloque a pasta em qualquer lugar (ex: `C:\AICS`)
2. Certifique-se de que `nssm.exe` está na pasta
3. Clique com o botão direito em **`setup.ps1`** → **Executar com PowerShell**

O instalador cuida de tudo automaticamente (eleva para Administrador via UAC sem interação adicional).

---

## Estrutura

```text
AICS\
├── setup.ps1         ← instalador unificado (execute este)
├── ativar-ics.ps1    ← lógica principal do serviço
├── tray.ps1          ← ícone de bandeja (status em tempo real)
├── config.txt        ← configuração da interface privada e IP
└── nssm.exe          ← gerenciador de serviço (incluir manualmente)
```

---

## Configuração

Edite o arquivo `config.txt` antes de instalar:

```ini
interface=Ethernet 2
private_ip=10.10.10.1
```

| Chave        | Descrição                                      |
|--------------|------------------------------------------------|
| `interface`  | Nome exato da interface de rede privada        |
| `private_ip` | IP fixo atribuído à interface privada          |

Se o `config.txt` não existir, os valores acima são usados como padrão.

---

## Como funciona

Após a instalação:

- O **AICS-Service** inicia automaticamente com o Windows
- O script detecta a interface com internet (rota padrão)
- Ativa o ICS entre a interface pública e a privada
- Atribui IP fixo à interface privada
- O **ícone na bandeja** exibe o status em tempo real (verde = ativo, vermelho = parado)
- Tray inicia automaticamente com o Windows

---

## Ícone de bandeja

Menu disponível ao clicar no ícone:

| Opção              | Ação                              |
|--------------------|-----------------------------------|
| ● Ativo / ○ Parado | Status atual (somente leitura)    |
| Abrir log          | Abre `aics.log` no Notepad        |
| Reiniciar serviço  | Reinicia o AICS-Service           |
| Iniciar / Parar    | Liga ou desliga o serviço         |
| Sair               | Fecha o ícone (serviço continua)  |

---

## Logs

| Arquivo            | Conteúdo                                      |
|--------------------|-----------------------------------------------|
| `C:\AICS\aics.log` | Erros e eventos relevantes com timestamp      |

Rotação automática ao atingir **5 MB** (mantém o arquivo atual + 1 backup).

Apenas eventos relevantes são registrados (erros e mudanças reais). Execuções sem alteração não geram entradas.

---

## Desinstalar

```powershell
# Remove o serviço
C:\AICS\nssm.exe remove AICS-Service confirm

# Remove o tray do startup
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "AICS-Tray"
```

---

## Requisitos

- Windows 10 ou superior
- PowerShell (já incluso no Windows)
- `nssm.exe` na pasta do projeto
- Serviço ICS do Windows habilitado (`SharedAccess`)
