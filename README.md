# SpyWater

Aplicativo nativo para macOS + integração para **Claude Code** e **Antigravity / Gemini** para acompanhar e controlar suas sessões em paralelo a partir de um painel e da barra de menus.

## O que ele faz

- **Visão ao vivo (Claude Code & Antigravity):** projeto, título, origem (`Claude Code` / `Antigravity`), atividade atual (comando Bash/`run_command`, edição de arquivo, busca, subagentes), modelo, esforço, custo estimado e uso da janela de contexto (com alerta visual a partir de 80% sugerindo `/compact`).
- **Filtros por origem e prioridade para pendências:** filtre entre Todos, Claude Code ou Antigravity; sessões aguardando permissão, resposta (`AskUserQuestion` / `ask_question`), aprovação de plano (`ExitPlanMode`), erro ou sua próxima instrução sobem automaticamente para o topo.
- **Allow / Deny e perguntas direto do app:** aprove comandos, edições e permissões, aprove com regras sugeridas ("Sempre permitir"), negue com instrução, responda perguntas de múltipla escolha/texto livre ou aprove/rejeite planos. Quando preferir, clique em **Responder no terminal** / **Responder no Antigravity**.
- **Uso do plano:**
  - **Claude Code:** barras para limite de **5 horas** e **semanal** via status line (com cache local) + tokens/turnos/custo/modelos locais.
  - **Antigravity / Gemini:** tokens, turnos e top modelos nas janelas de **5 horas**, **7 dias** e **hoje** lidos dos transcripts locais.
- **Retomar / abrir sessões:** retome sessões encerradas do Claude Code (`claude --resume`) no Terminal ou iTerm, ou foque rapidamente o Antigravity.

## Estrutura do repositório

- `.claude-plugin/marketplace.json` — marketplace local para instalação no Claude Code
- `plugin/` — plugin `spywater` e hooks (`spy-hook.sh`, `agy-hook.sh`, `statusline-tee.sh`)
- `app/` — aplicativo SwiftUI nativo para macOS 14+ (`SpyWater.app`)
- `scripts/` — build do app, integração da status line e hooks do Antigravity, e auto-teste

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

### 3. Integrar a status line do Claude Code (limites 5h / semanal)

```bash
./scripts/install-statusline.sh
```

### 4. Instalar os hooks do Antigravity / Gemini

```bash
./scripts/install-agy-hooks.sh
```

Esse script configura a entrada `"spywater"` em `~/.gemini/config/hooks.json` (fazendo backup em `~/.gemini/config/hooks.json.spywater-bak` se o arquivo já existir). Além dos hooks, o SpyWater também lê diretamente `~/.gemini/antigravity/conversation_summaries.db` e os `transcript.jsonl` locais para mostrar conversas já abertas, modelo e uso de contexto.

## Como usar

1. Abra o `SpyWater.app` (ele aparece no Dock e na barra de menus).
2. Use o `claude` no terminal ou o **Antigravity** normalmente.
3. Pedidos de permissão e perguntas aparecem no painel e na barra de menus; se você não responder dentro do tempo configurado (padrão: 2 minutos), o pedido é devolvido automaticamente.
4. Opcional: em **Configurações**, ative *"Interceptar comandos (run_command) do Antigravity para aprovar no SpyWater"* se quiser aprovar comandos do Antigravity direto pelo app.

## Como desinstalar

```bash
./scripts/uninstall-statusline.sh
./scripts/uninstall-agy-hooks.sh
claude plugin uninstall spywater@spywater-local
claude plugin marketplace remove spywater-local
rm -rf ~/Applications/SpyWater.app ~/.spywater
```

## Limitações conhecidas

- No Claude Code, interromper uma resposta com `Esc` no terminal não dispara o hook `Stop`, então a sessão pode ficar como "Trabalhando" até o próximo evento.
- Os percentuais oficiais de limite do plano do Claude (5h / semanal) aparecem logo após a primeira resposta da sessão com o wrapper da status line ativo.
- No Antigravity, respostas a `ask_question` pelo SpyWater funcionam injetando a resposta escolhida via `deny` + `reason` no hook `PreToolUse`, enquanto permissões (`ask_permission` ou `run_command`) usam `auto_approve` / `deny`.
- Troca de modelo e envio de texto arbitrário para terminais sem tmux ainda não fazem parte desta versão.
