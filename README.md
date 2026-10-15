# notfcode — seu painel de uso de IA no desktop

O **notfcode** mantém os limites e a atividade das suas ferramentas de IA visíveis em uma pequena interface junto à borda da tela. A ideia é simples: conferir quanto da cota ainda resta e perceber quando um agente está trabalhando ou aguardando uma ação, sem precisar alternar entre várias janelas.

Este repositório reúne duas implementações: o aplicativo nativo em Swift para macOS e o aplicativo multiplataforma em Rust + Tauri para Windows e Linux. A versão Linux é executada como uma janela X11/XWayland para poder permanecer posicionada junto à borda da tela.

## Recursos

- Indicadores circulares de uso, com cores que ajudam a identificar limites próximos do fim.
- Cartão contextual com períodos de cota, dados da conta e horários de renovação quando o provedor informa esses valores.
- Detecção de atividade de agentes e alertas de conclusão, aprovação ou resposta pendente quando o provedor oferece sinais compatíveis.
- Fontes de dados locais e remotas para serviços de IA, incluindo Claude Code, Codex, Cursor, Antigravity, OpenCode, GitHub Copilot, Grok, GLM, Kimi, Kiro, Amp, Apify e ferramentas locais como Ollama, LM Studio, oMLX e llama.cpp.
- Configurações de aparência, posicionamento, provedores ativos e atualização manual.
- Integração opcional com um celular por meio do protocolo Phone Link documentado no repositório.

A disponibilidade de cada indicador depende da ferramenta estar instalada, autenticada e fornecer dados compatíveis. A aplicação não inventa uma porcentagem quando não há um valor confiável.

## Sistemas compatíveis

| Sistema | Implementação | Estado |
|---|---|---|
| macOS 15 ou posterior | Swift, SwiftUI e AppKit | Aplicativo nativo; compilação exige macOS e Xcode |
| Windows 10/11 | Rust + Tauri 2 | Aplicativo de desktop e instalador NSIS |
| Linux (x86-64) | Rust + Tauri 2 | Compilação e execução disponíveis; requer GTK/WebKitGTK e sessão gráfica |
| Linux com Wayland | Rust + Tauri 2 | Executa o posicionamento do painel via XWayland/X11 |

**Observação:** a interface Swift/SwiftUI é específica do macOS. No Linux, use o projeto Tauri em `windows/`; essa pasta contém a implementação Rust compartilhada por Windows e Linux. Algumas integrações exclusivas do Windows ainda não existem no Linux; veja `windows/README.md`.

## Compilar e executar no Linux

### Debian e Ubuntu

Instale as dependências de compilação e da interface gráfica:

```bash
sudo apt update
sudo apt install -y build-essential pkg-config libssl-dev \
  libwebkit2gtk-4.1-dev libgtk-3-dev \
  libayatana-appindicator3-dev librsvg2-dev
```

Instale uma versão estável do Rust usando o instalador oficial de `rustup` e instale o Node.js/npm se também quiser gerar pacotes Tauri. Em seguida, na raiz do repositório:

```bash
make build
make test
make run
```

O primeiro build pode demorar porque algumas dependências nativas e o SQLite são compilados. O comando `make run` usa `windows/scripts/run-linux.sh`, que prepara o ambiente para o desktop Linux e inicia o aplicativo.

Para criar pacotes `.deb` e AppImage, instale o Node.js/npm e execute:

```bash
make linux-package
```

É possível usar os comandos diretamente na pasta Rust:

```bash
cd windows
cargo build --release --locked -p notfcode
cargo test --locked
./scripts/run-linux.sh
```

### Outras distribuições

É necessário ter Rust/Cargo, um compilador C, `pkg-config`, OpenSSL, GTK 3, WebKitGTK 4.1, Ayatana AppIndicator e librsvg em versões compatíveis com a distribuição. Os nomes dos pacotes variam entre Debian/Ubuntu, Fedora, Arch e derivados; instale os equivalentes oferecidos pela sua distribuição.

### Wayland, XWayland e indicador da bandeja

O painel precisa permanecer junto à borda da tela. Como o Wayland não permite que um cliente posicione livremente suas janelas, o script inicia a interface pelo XWayland. Em ambientes GNOME, talvez seja necessário habilitar a extensão **AppIndicator Support** para mostrar o ícone da bandeja.

Se o aplicativo for iniciado a partir de um terminal distribuído como Snap, variáveis de ambiente do Snap podem interferir com a biblioteca C do sistema. O script de inicialização remove essas variáveis e escolhe o backend X11 para reduzir esse problema.

## Compilar no macOS

A versão nativa requer macOS, Xcode, XcodeGen e as ferramentas de linha de comando da Apple. No Terminal, na raiz do projeto:

```bash
make gen
make build
make test
make run
```

No macOS, esses comandos são encaminhados para o Makefile nativo. As instruções de assinatura, empacotamento e atualização ficam na documentação de desenvolvimento e não se aplicam ao build Linux. O instalador antigo foi removido porque ainda carregava a identidade anterior; antes de publicar uma versão macOS, gere e assine um novo `.dmg` e atualize o feed conforme `site/README.md`.

## Dados, privacidade e credenciais

O notfcode reaproveita sessões locais de ferramentas que você já utiliza quando isso é necessário ao provedor. A leitura de credenciais deve permanecer local; não publique arquivos de configuração, bancos SQLite, registros de sessão, tokens nem capturas que contenham dados privados ao enviar relatórios de erro.

Quando a fonte oferece apenas dados aproximados, derivados de registros ou contagem de requisições, a interface indica essa limitação. Endpoints internos de fornecedores podem mudar sem aviso e exigir atualização do adaptador. Consulte a documentação específica em `docs/providers/`.

## Organização do repositório

- `Sources/` — aplicativo nativo para macOS, provedores, interface e recursos.
- `Tests/` — testes unitários e testes de regressão do aplicativo Swift.
- `windows/notfcode/` — aplicativo Rust/Tauri de desktop usado no Windows e no Linux.
- `windows/notfcode-hook/` — auxiliar de eventos usado pela integração com os hooks do Claude Code.
- `windows/scripts/run-linux.sh` — inicializador da versão Linux.
- `docs/` — especificações, decisões técnicas e documentação dos provedores.
- `PHONE-LINK-V3.md` e `docs/phone-link-protocol.md` — especificação da comunicação segura com o cliente móvel.
- `TASKS.md` — resumo dos componentes e do histórico técnico.

## Testes

Na raiz, use `make test`. Para executar os testes da implementação Rust:

```bash
cd windows
cargo test --locked
node --test test-codex-headline.cjs
```

Os testes de provedores devem usar dados sintéticos sempre que possível. Não inclua tokens ou conteúdo real de contas nos fixtures.

## Limitações conhecidas no Linux

O painel, o cartão flutuante, as configurações, a bandeja e a maioria dos provedores compartilham a implementação Tauri. Alguns recursos que dependem da API Win32 — como determinados métodos de arrastar a cápsula, detecção da janela em primeiro plano e leitura de credenciais do Gerenciador de Credenciais do Windows — ainda precisam de equivalentes específicos para Linux. Isso não impede a compilação geral; os detalhes estão em `windows/README.md`.

## Contribuir

Antes de enviar uma alteração, descreva o comportamento esperado, os sistemas em que foi testado e eventuais limitações. Para mudanças visuais, inclua capturas sem dados pessoais. Para alterações nos adaptadores, adicione testes com respostas fictícias e documente a origem do dado.

## Licença

Consulte o arquivo [`LICENSE`](LICENSE) e os avisos de terceiros distribuídos junto aos recursos.
