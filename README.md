# AICS — Automatic Internet Connection Sharing Service

Serviço automático para Windows que configura e mantém o compartilhamento de internet (ICS) ativo de forma persistente.

Funciona como um **roteador virtual**, compartilhando a conexão principal com uma interface secundária (ex: Ethernet, impressora, rede local).

---

## Instalação

1. Coloque a pasta em qualquer lugar (ex: `C:\AICS`)
2. Certifique-se de que `nssm.exe` está na pasta
3. Edite `config.txt` com o nome correto da sua interface
4. Dê duplo clique em **`INSTALAR.bat`** e aceite o UAC

O instalador cuida de tudo automaticamente.

---

## Estrutura

```text
AICS\
├── INSTALAR.bat      ← execute este para instalar
├── DESINSTALAR.bat   ← execute este para desinstalar
├── STATUS.bat        ← diagnóstico rápido (duplo clique)
├── setup.ps1         ← lógica do instalador (chamado pelo INSTALAR.bat)
├── desinstalar.ps1   ← lógica do desinstalador
├── ativar-ics.ps1    ← serviço principal (ICS + monitoramento)
├── tray.ps1          ← ícone de bandeja (status em tempo real)
├── verificar.ps1     ← verificação completa do sistema
├── config.txt        ← configuração da interface privada e IP
└── nssm.exe          ← gerenciador de serviço (incluir manualmente)
```

---

## Configuração

Edite o arquivo `config.txt` antes de instalar:

```ini
interface=Ethernet
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
- Entra em **loop de monitoramento** (verifica a cada 60s e reaplica se necessário)
- O **ícone na bandeja** exibe o status em tempo real (verde = ativo, vermelho = parado)
- Tray inicia automaticamente com o Windows

## Diagnóstico

| Ferramenta       | Como usar                        | O que mostra                              |
|------------------|----------------------------------|-------------------------------------------|
| `STATUS.bat`     | Duplo clique                     | Status rápido: serviço, ICS, log          |
| `verificar.ps1`  | PowerShell (Admin)               | Verificação completa com todos os checks  |

---

## Ícone de bandeja

Menu disponível ao clicar no ícone:

| Opção                | Ação                              |
|----------------------|-----------------------------------|
| [ON] / [OFF] Serviço | Status atual (somente leitura)    |
| Abrir log            | Abre `aics.log` no Notepad        |
| Reiniciar servico    | Reinicia o AICS-Service           |
| Iniciar / Parar      | Liga ou desliga o serviço         |
| Sair                 | Fecha o ícone (serviço continua)  |

---

## Logs

| Arquivo            | Conteúdo                                      |
|--------------------|-----------------------------------------------|
| `C:\AICS\aics.log` | Erros e eventos relevantes com timestamp      |

Rotação automática ao atingir **5 MB** (mantém o arquivo atual + 1 backup).

Apenas eventos relevantes são registrados (erros e mudanças reais). Execuções sem alteração não geram entradas.

---

## Desinstalar

Dê duplo clique em **`DESINSTALAR.bat`** e aceite o UAC.

O que o desinstalador faz, em ordem:

1. Para e remove o **AICS-Service**
2. Remove o **ícone de bandeja** do startup do Windows
3. Encerra o processo do tray se estiver rodando
4. Remove o **IP fixo** da interface `Ethernet`
5. Apaga a pasta **`C:\AICS`** completamente

Após concluir, a conexão compartilhada é desativada e o Windows volta ao comportamento padrão.

---

## Requisitos

- Windows 10 ou superior
- PowerShell (já incluso no Windows)
- `nssm.exe` na pasta do projeto
- Serviço ICS do Windows habilitado (`SharedAccess`)
