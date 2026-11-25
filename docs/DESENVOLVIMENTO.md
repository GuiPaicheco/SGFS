# Desenvolvimento e testes

Use Node.js 24 e Python 3.14. Os testes da cadeia de migrações usam Docker, Supabase CLI 2.118.0 e PostgreSQL 17. O [workflow do GitHub](../.github/workflows/tests.yml) registra a sequência completa.

## Executar os testes

```sh
node scripts/check-public-repository.mjs
node --test tests/*.test.mjs
python -m pip install -r requirements.txt
python -m unittest discover -s tests -p 'test_cnes*.py'
```

O verificador examina os arquivos rastreados e indica padrões bloqueados sem imprimir valores. Use uma base descartável para os ensaios SQL e fixtures.

## Interface e serviço local

Siga a [implantação integrada](../local/IMPLANTACAO.md) em um banco de desenvolvimento. Configure as variáveis do processo conforme [.env.example](../.env.example). Execute `node local/integrado.mjs` para gerar a interface e iniciar os serviços. A saída pública é `dist-municipal/`. A entrada da API Python é `api.cnes:app`.

Para gerar somente a interface, configure `SGFS_MUNICIPAL_PUBLIC_KEY` e `SGFS_BROWSER_SDK_FILE` e execute `node scripts/build-static.mjs`. A saída espera as rotas do gateway no mesmo endereço da interface.

## Ferramentas de ensaio

- `scripts/prepare-workflow-rehearsal.mjs` gera ensaios SQL transacionais do CI.
- `scripts/prepare-demo.mjs` gera uma demonstração com rollback por padrão.
- `scripts/verify-database-rebuild.mjs` compara uma restauração sintética em banco Docker isolado.
- `local/testar-*` e `local/ensaiar-lancamento.sql` verificam a instalação local provisionada.
- Os ensaios autenticados do piloto anterior que apontavam para a instalação hospedada estão no histórico Git.
