# SpyWater

Aplicativo nativo para macOS + plugin do Claude Code para acompanhar e controlar suas sessões do Claude em paralelo a partir de um painel e da barra de menus.

## O que ele faz

- **Visão ao vivo de todas as sessões:** projeto, título, atividade atual (comando Bash, edição de arquivo, busca, subagentes), modelo, esforço, custo estimado e uso da janela de contexto (com alerta visual a partir de 80% sugerindo `/compact`).
- **Prioridade para o que precisa de você:** sessões aguardando permissão, resposta (`AskUserQuestion`), aprovação de plano (`ExitPlanMode`), erro ou sua próxima instrução sobem automaticamente para o topo.
- **Allow / Deny e perguntas direto do app:** aprove comandos e edições, aprove com regras sugeridas ("Sempre permitir"), negue com instrução, responda perguntas de múltipla escolha/texto livre ou aprove/rejeite planos. Quando preferir, clique em **Responder no terminal** para devolver o prompt ao terminal.
- **Uso do plano:** barras para limite de **5 horas** e **semanal**, alimentadas via wrapper da status line do Claude Code.
- **Retomar sessões encerradas:** lista sessões recentes dos últimos 7 dias com botão **Retomar** (`claude --resume`) no Terminal ou iTerm.

## Estrutura do repositório

- `.claude-plugin/marketplace.json` — marketplace local para instalação no Claude Code
- `plugin/` — plugin `spywater` com os hooks e scripts (`spy-hook.sh` e `statusline-tee.sh`)
- `app/` — aplicativo SwiftUI nativo para macOS 14+ (`SpyWater.app`)
- `scripts/` — build do app, integração da status line e auto-teste

## Como compilar e instalar

### 1. Compilar o app

```bash
./scripts/build-app.sh
```

O script compila em release com SwiftPM e instala o bundle assinado localmente em `~/Applications/SpyWater.app`.

### 2. Instalar o plugin no Claude Code

```bash
claude plugin marketplace add /Users/leonardocruz/Desktop/spywater
claude plugin install spywater@spywater-local
```

### 3. Integrar a status line (opcional, necessário para limites 5h / semanal)

```bash
./scripts/install-statusline.sh
```

Esse script faz backup de `~/.claude/settings.json` em `~/.claude/settings.json.spywater-bak`, preserva seu script original de status line em `~/.spywater/statusline-original` e passa a encaminhar os dados para o SpyWater antes de executar seu script original.

## Como usar

1. Abra o `SpyWater.app` (ele aparece no Dock e na barra de menus).
2. Use o `claude` normalmente em seus terminais.
3. Pedidos de permissão e perguntas aparecem no painel e na barra de menus; se você não responder dentro do tempo configurado (padrão: 2 minutos), o pedido é liberado de volta ao terminal automaticamente.

## Como desinstalar

```bash
./scripts/uninstall-statusline.sh
claude plugin uninstall spywater@spywater-local
claude plugin marketplace remove spywater-local
rm -rf ~/Applications/SpyWater.app ~/.spywater
```

## Limitações conhecidas

- Sessões abertas **antes** da instalação do plugin só aparecem após o próximo evento/resposta ou na lista de recentes via transcript.
- Interromper uma resposta com `Esc` no terminal não dispara o hook `Stop`, então a sessão pode continuar como "Trabalhando" até o próximo evento.
- Os limites de uso do plano (5h / semanal) só aparecem depois da primeira resposta de uma sessão rodando com o wrapper da status line ativo.
- Troca de modelo e envio de texto arbitrário para terminais sem tmux ainda não fazem parte desta versão (MVP).
