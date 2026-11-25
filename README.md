# SGFS — Sistema de Gestão de Funcionários da Saúde

Aplicação web para organizar profissionais, calendários, férias e afastamentos de equipes de saúde. A distribuição principal usa PostgreSQL com Supabase Auth, PostgREST, funções em Deno e o gateway Node.js.

## Executar localmente

Com o banco PostgreSQL provisionado e os componentes configurados, execute `node local/integrado.mjs`. A instalação Windows já provisionada também pode usar [Iniciar SGFS.cmd](local/Iniciar%20SGFS.cmd). O endereço local padrão é `http://127.0.0.1:8089/SGFS/`. Consulte o [guia de implantação](local/IMPLANTACAO.md) para os requisitos, a restauração da base e a atualização do esquema.

## Configuração

Use [.env.example](.env.example) como referência para as variáveis do processo. A aplicação não carrega automaticamente arquivos `.env`. Nunca coloque `SUPABASE_SERVICE_ROLE_KEY` na interface. O gateway gera a chave pública a partir do segredo institucional e a inclui no build em `dist-municipal/`.

## Testes e build

Execute `node --test tests/*.test.mjs` e os [testes Python](docs/DESENVOLVIMENTO.md). O CI testa a cadeia de migrações em PostgreSQL com a pilha Supabase local. O gateway gera a interface integrada na inicialização.

## Estrutura

- `index.html` e `assets/` contêm a interface e as bibliotecas de navegador.
- `local/` contém o gateway, o inicializador Windows e ensaios da instalação integrada.
- `api/` e `cnes_service/` consultam a fonte CNES.
- `supabase/` contém as migrações PostgreSQL e as funções de backend. Os papéis históricos RH/Diretor permanecem nas estruturas de compatibilidade.
- `docs/` contém o manual, a arquitetura e os procedimentos de operação.

## Implantação e manutenção

Baixe o [ZIP do SGFS](https://github.com/GuiPaicheco/SGFS/archive/refs/heads/main.zip) e siga o [guia de implantação no servidor](local/IMPLANTACAO.md). Para publicar a interface via Vercel, consulte [hospedagem](docs/HOSPEDAGEM.md).

## Licença

Consulte [LICENSE](LICENSE) para as condições de uso.
