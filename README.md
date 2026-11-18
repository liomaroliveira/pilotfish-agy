# Pilotfish for Antigravity (`pilotfish-agy`)

Port adaptado do [Nanako0129/pilotfish](https://github.com/Nanako0129/pilotfish) (`v1.5.0`) para o **Google Antigravity**, com descoberta ao vivo de modelos + níveis de thinking + cotas, modo híbrido configurável (Gemini ↔ Claude ↔ GPT), precedência para subagentes especialistas do projeto e integração explícita com o ecossistema nativo do Antigravity.

---

## Como funciona na `v1.5.0-agy.5`

### 1. Descoberta ao vivo de modelos, thinking e cotas
Antes de qualquer delegação não-trivial, o Pilotfish chama `swarm(action: "models", all: true)` (custo zero) para ler em tempo real:
- Quais modelos estão habilitados na conta atual (Plus, Pro, Flash-only etc.), já separados por nível de thinking/effort (`-low`, `-medium`, `-high`, `-extra`, `-thinking`);
- A cota restante (`quota_remaining`) e o reset (`quota_resets`) de cada um.

Com isso, ele descarta modelos abaixo do `quotaFloorPercent` (padrão `10%`), protege modelos configurados em `protectModels` (padrão `["argon"]`) e agrupa dinamicamente os modelos saudáveis em **3 faixas relativas à conta**:
- **Faixa 1 — Leve (`recon`):** menor thinking/custo saudável disponível *(ex.: só Flash → `Flash Low`; na Pro → `Hydrogen Low`)*.
- **Faixa 2 — Média (`exec`):** thinking intermediário saudável *(ex.: `Flash Medium`, `Claude Sonnet 4.6`, `Hydrogen Medium`)*.
- **Faixa 3 — Forte (`frontier`):** modelo/thinking mais forte e saudável disponível *(ex.: `Claude Opus 4.6` se `crossPoolRouting: true` e cota livre; `Hydrogen High/Extra` na Pro; `Flash High` em conta só Flash)*.

### 2. Modos de roteamento configuráveis (`config.json`)

| Opção | Padrão | Valores / Efeito |
| --- | --- | --- |
| `routingMode` | `"hybrid"` | `"hybrid"` (combina `invoke_subagent` com allowlists/MCPs + `swarm` para thinking exato/troca de pool), `"subagent"` (só `invoke_subagent`/`run_workflow`), `"swarm"` (todos via `swarm` com IDs exatos) |
| `crossPoolRouting` | `true` | Permite balancear/migrar entre pools saudáveis (ex.: Gemini ↔ Claude ↔ GPT) quando um pool atinge o piso ou outro pool mais forte está livre |
| `quotaFloorPercent` | `10` | Piso de cota restante (`0`–`90`, ex.: `5` ou `10`) abaixo do qual o modelo/pool é protegido |
| `protectModels` | `["argon"]` | Substrings de modelos protegidos contra disparo automático rotineiro |
| `projectAgentPrecedence` | `true` | Subagentes especialistas do projeto (ex.: `vega-*` no `firetv-dev`) têm prioridade; os `pf-*` atuam como complemento (revisão independente, busca genérica e fallback) |
| `autoResumeOnQuotaReset` | `true` | Salva checkpoint e agenda timer (`schedule`) para auto-despertar no reset de cota |
| `networkGuard` | `enabled: true` | Monitor de rede local zero-token (`pilotfish-net-watchdog.py`): probe ultrarrápido (<30ms), pausa segura sem queimar retries e reativação reativa automática |
| `safetyGuard` | `enabled: true` | Hook `PreToolUse` determinístico (`deny` em secrets/destruição catastrófica, `force_ask` em arquivos sensíveis) |

**Como configurar (global, por projeto ou inline no prompt):**

```bash
# Ver configuração global atual:
make config-show

# Alterar configuração global (~/.gemini/config/plugins/pilotfish-agy/config.json):
./scripts/configure.sh --global --mode hybrid --cross-pool on --quota-floor 5 --network-guard on

# Criar override específico só para um projeto (<projeto>/.agents/pilotfish.config.json):
./scripts/configure.sh --project /caminho/do/projeto --mode subagent --quota-floor 10 --cross-pool off

# Ou sobrescrever pontualmente no prompt:
# "Use pilotfish (mode=swarm, floor=5%, cross_pool=on): ..."
```

### 3. Ecossistema nativo do Antigravity (explicitado na política)
O `pilotfish-agy` compõe explicitamente com — e nunca suprime — as capacidades nativas do Antigravity:
- **Subagentes nativos:** `research` (sandbox read-only sem rede), `browser` (UI web / localhost ao vivo), `image-generator` (logos/ativos)
- **Orquestração nativa:** `invoke_subagent`, `run_workflow` (`parallel`/`pipeline`/`phase`), `swarm` (`models`/`add`/`model`/`status`)
- **Interação & automação:** `ask_question`, `schedule`, `run_command`, `manage_task`, `search_web`
- **Extensibilidade:** servidores MCP (`call_mcp_tool`, `list_resources`, `read_resource`), todas as **Skills** (globais e do projeto) e **Plugins** instalados
- **Slash commands da UI:** compõe naturalmente com `/plan`, `/grill-me`, `/goal`, `/teamwork`, `/boost`, `/compact`, `/learn`, `/schedule`, `/browser` e `/btw`

---

## Como instalar ou portar para qualquer projeto

```bash
# Clonar o repositório:
git clone https://github.com/liomaroliveira/pilotfish-agy.git
cd pilotfish-agy

# Instalar globalmente (~/.gemini/config/plugins/pilotfish-agy):
make install-global

# Instalar em qualquer projeto (<projeto>/.agents/plugins/pilotfish-agy):
make install-project DIR=/caminho/do/seu-projeto

# Ou baixar direto da GitHub Release sem clonar o repo:
mkdir -p /caminho/do/projeto/.agents/plugins
curl -sL https://github.com/liomaroliveira/pilotfish-agy/releases/latest/download/pilotfish-agy-v1.5.0-agy.2.tar.gz \
  | tar -xz -C /caminho/do/projeto/.agents/plugins
```

## Build, testes e geração de releases

```bash
make validate                                # Valida manifesto, config, rule (<24KB), skill e 7 agentes
make build                                   # Gera bundle limpo em dist/pilotfish-agy/
make test                                    # Roda suite automatizada (incluindo install e configure)
make release                                 # Gera .tar.gz, .zip, kit portável, SHA256SUMS.txt e RELEASE-NOTES.md
./scripts/release.sh --version 1.5.0-agy.3   # Gera nova versão empacotada
```

## Licença e atribuição
Licença MIT — veja [LICENSE](./LICENSE) e [ATTRIBUTION.md](./ATTRIBUTION.md).
