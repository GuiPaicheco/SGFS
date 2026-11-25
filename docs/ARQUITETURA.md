# Arquitetura do SGFS

## Visão geral

```text
Navegador — index.html e assets/
  └─ Gateway Node.js — local/integrado.mjs
       ├─ Supabase Auth — sessões e recuperação de acesso
       ├─ PostgREST — Data API protegida por RLS
       ├─ Deno — funções de supabase/functions/
       └─ Uvicorn — /api/cnes, exclusivo da Administração

Auth, PostgREST e as funções usam a base PostgreSQL do SGFS.
  ├─ auth — contas e sessões
  ├─ public — cadastros e relações protegidos por RLS
  └─ private — fonte CNES, registros RH e operadores
```

O frontend é uma aplicação estática sem framework. `assets/app.js` coordena sessão, navegação e módulos especializados. O build versiona assets pelo conteúdo e publica apenas uma lista de arquivos. Bibliotecas locais de exportação são carregadas quando necessárias.

A instalação integrada serve a interface e as rotas de backend pelo gateway. Para a publicação na Vercel, o build gera os mesmos arquivos do cliente e uma configuração separada com a chave pública do ambiente. As rotas de Auth, dados e CNES são encaminhadas ao gateway HTTPS quando configurado. [Hospedagem](HOSPEDAGEM.md)

## Acessos vigentes

- **Público:** entrada e simulação sem persistir um lançamento.
- **Administração:** consulta e incorporação CNES, autorização dos operadores, feriados e visão das unidades.
- **RH institucional:** conta vinculada a uma unidade; identifica um profissional previamente autorizado antes de operar.

A identidade declarada do operador é registrada junto das ações; uma conta compartilhada não equivale à autenticação individual desse profissional. Essa limitação exige política institucional de uso e evolução conforme as pendências.

Esconder uma aba não é autorização. As funções de servidor revalidam usuário, papel, situação, contexto de unidade e operador conforme a operação. Cabeçalhos enviados pelo navegador não devem ser tratados isoladamente como prova de permissão.

O gateway verifica o aceite da sessão e a exigência de trocar a senha provisória antes de liberar as operações. A autorização por papel, unidade e operador permanece nas funções de backend e no banco.

## Cadastros e lançamentos

`config/rh-units.json` limita as unidades consultáveis. A API Python valida o token e o perfil administrativo antes da coleta e não grava cadastros. Dados completos são comparados pelo servidor; a Administração decide as inclusões e alterações. Ausência na coleta não implica desligamento.

Registros CNES e vínculos operacionais têm IDs estáveis. Férias, folgas, aniversários e histórico do RH permanecem separados dos dados importados. Remoção do uso ativo é versionada e não equivale a apagar o histórico.

As funções PostgreSQL mantêm as regras transacionais de lançamento, conflitos, alterações, cancelamento e recálculo. A prévia do navegador não substitui a validação no servidor nem a conferência dos assentamentos.

## Estruturas de compatibilidade

Tabelas antigas de solicitações, aprovações, saldo de banco de horas e cadastro por CPF/matrícula permanecem na cadeia de migrations por compatibilidade. Não são o fluxo atual do produto. O mesmo vale para identificadores internos SGF e papéis históricos RH/Diretor. Não remover estruturas de banco sem análise de dependências e migração explícita.

## Limites

- O CNES pode estar indisponível ou incompleto; erros não podem ser convertidos em lista vazia para incorporação.
- O cache de coleta é temporário e por instância; não é um limitador global distribuído.
- Importação do CNES não comprova direito, saldo ou enquadramento normativo.
- Testes de contrato e ensaios SQL não substituem aceite de uso, visualização e impressão.
- Autorização, backup, retenção, monitoramento e responsabilidades institucionais dependem da configuração e da operação do ambiente.

Veja [desenvolvimento](DESENVOLVIMENTO.md), [publicação](PUBLICACAO.md) e [privacidade](PRIVACIDADE.md).
