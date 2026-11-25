# SGFS no ambiente institucional

A versão integrada usa o frontend original, PostgreSQL, PostgREST, Supabase Auth executado no próprio servidor, Deno para as funções TypeScript e Uvicorn para a API CNES. A instalação usa credenciais e processos próprios. O navegador acessa somente o endereço do SGFS. A coleta CNES exige acesso de saída do servidor ao Datasus.

## Ensaio Windows com ambiente provisionado

Na pasta do projeto, abra [Iniciar SGFS.cmd](Iniciar%20SGFS.cmd) e acesse `http://127.0.0.1:8089/SGFS/`. O inicializador requer Node.js 24 no PATH, PostgreSQL local já provisionado e binários e segredos protegidos pelo Windows em `%LOCALAPPDATA%/SGFS-runtime`. O banco integrado usa o PostgreSQL local na porta 55432, separado do banco de ensaio anterior e do servidor municipal. A caixa de e-mails de ensaio abre em `http://127.0.0.1:19026/`. Ela captura mensagens localmente. Pressione Ctrl+C para encerrar o gateway e seus serviços auxiliares. O PostgreSQL é administrado separadamente.

O inicializador espera os arquivos protegidos jwt.dpapi, auth.dpapi e rest.dpapi e os binários de Auth, PostgREST, Deno, Python e Mailpit. Para caminhos personalizados, use SGFS_RUNTIME, SGFS_POSTGRES_BIN e SGFS_POSTGRES_HOME. Para outras instalações, configure o ambiente do gateway diretamente. O modelo de variáveis está em [../.env.example](../.env.example).

## Publicação

- Configure `SGFS_SITE_URL` com a URL HTTPS oficial, incluindo `/SGFS/`. O proxy da Prefeitura deve repassar esse caminho e o cabeçalho de host para o processo Node em loopback. Os serviços internos devem permanecer em loopback.
- Configure `SGFS_AUTH_DATABASE_URL` e `SGFS_REST_DATABASE_URL` com contas de serviço separadas. A primeira administra o esquema Auth. A segunda alterna explicitamente entre os papéis do aplicativo conforme o token. Restaure as permissões e verifique as políticas RLS antes da publicação. Use validação de TLS para o PostgreSQL remoto conforme a configuração da TI.
- Aponte `SGFS_AUTH_EXE`, `SGFS_POSTGREST_EXE`, `SGFS_DENO_EXE`, `SGFS_PYTHON_EXE` e `SGFS_BROWSER_SDK_FILE` para os componentes instalados. O SDK precisa ser o bundle UMD da versão 2.117.2. Instale as dependências com `python -m pip install -r requirements.txt` no Python de serviço. Execute `deno cache --no-lock supabase/functions/*/index.ts` na raiz (ou passe a lista de arquivos explicitamente se o shell não expandir o padrão). Use a mesma conta de serviço para preencher o cache e executar o gateway.
- Guarde `SGFS_JWT_SECRET` no gerenciador de segredos do ambiente e configure o SMTP institucional com `SGFS_SMTP_HOST`, `SGFS_SMTP_PORT`, `SGFS_SMTP_USER`, `SGFS_SMTP_PASSWORD` e `SGFS_SMTP_FROM`. Nunca publique as credenciais de banco ou a chave de serviço. A geração de `dist-municipal` inclui apenas a chave pública.
- Execute `node local/integrado.mjs` com um gerenciador de serviços. Configure a conta, o reinício automático, o log e a verificação de saúde no ambiente municipal.
- Para a virada, tire um backup atualizado em uma janela sem novas gravações. Preserve as contas e os identificadores originais. Abra sessões novas no destino após a troca. Aprove os testes de login, recuperação, isolamento por unidade, lançamentos, auditoria e CNES antes de reabrir o acesso.

Provisione uma base de dados dedicada aos esquemas public, private e auth. Prepare e confira a restauração em um ambiente de teste antes da virada.
No Windows, o binário local de Auth foi compilado a partir de v2.198.0 com [o ajuste de escuta](auth-windows.patch), pois a versão oficial usa uma opção de socket Unix. Em Linux use o binário oficial correspondente.

## Restauração do banco

O ensaio integrado usou o arquivo em formato custom criado com `pg_dump`. Para reproduzir a restauração, a TI precisa de uma base vazia e de autorização para provisionar os papéis do SGFS no cluster.

1. Liste o arquivo com `pg_restore --list`. Preserve as entradas dos dados, das políticas e dos privilégios da aplicação. As ACLs restauradas fazem parte da autorização do PostgREST. Não use `--no-privileges` no banco integrado.
2. Confirme que `pg_stat_statements`, `pgcrypto` e `uuid-ossp` podem ser restauradas. O arquivo de origem também registra `supabase_vault`. O cofre estava vazio na cópia de ensaio. No PostgreSQL padrão, foram retiradas da lista apenas as entradas da extensão Vault, os dados de `vault.secrets` e as ACLs dos objetos internos dessa extensão.
3. Retire da lista as entradas de dados de `auth.sessions`, `auth.refresh_tokens`, `auth.one_time_tokens`, `auth.flow_state`, `auth.mfa_amr_claims`, `auth.mfa_challenges` e `private.rh_operator_sessions`. Mantenha as tabelas e os usuários. Isso permite que o novo serviço abra sessões e emita links novos.
4. Prepare os papéis `anon`, `authenticated`, `service_role`, `supabase_auth_admin` e os demais papéis referenciados nas ACLs originais. No ensaio, o papel autenticador do PostgREST recebeu `LOGIN NOINHERIT` e permissão para alternar entre os três primeiros. `service_role` ficou sem login e com `BYPASSRLS`, para as funções privilegiadas do backend. Somente a conta do Auth pode assumir a propriedade do esquema `auth` e de suas tabelas. A TI precisa revisar impactos de papéis existentes no cluster antes de reaproveitá-los.
5. Use `pg_restore --single-transaction --exit-on-error --no-owner --use-list` com a lista revisada e a base vazia. Ajuste o proprietário do esquema `auth` e das tabelas desse esquema para a conta do Auth. Revogue a conexão da base de `PUBLIC` e permita a conexão às contas de serviço necessárias.
6. Compare ao backup as contagens, vínculos, ACLs e políticas da base restaurada. Confira também o histórico de migrações antes de aplicar as atualizações pendentes.

A instalação existente segue como origem durante o ensaio. Após o corte, mantenha uma única instalação apta a receber gravações oficiais.


## Atualizações do piloto

A versão 1.1.0 exige a migração SQL de melhorias do piloto antes de iniciar o gateway. Publique a interface e a API na mesma janela para manter a paginação e o aceite compatíveis. A versão integrada checa o aceite da sessão e a troca de senha provisória no gateway. Deixe Auth, PostgREST e as funções internas acessíveis somente pelo gateway.

As contas existentes conservam suas senhas até a Administração selecionar **Resetar senha** e combinar a troca com a unidade. A recuperação por e-mail de Administração continua disponível. Valide os Termos de Uso e o Aviso de Privacidade com a Prefeitura antes de liberar esta versão para o piloto. Para mudar os documentos, atualize a versão exibida na interface e a versão exigida pela RPC na mesma implantação.

As novidades ficam em assets/sgfs-releases.js. Para preparar a publicação, gere as notas com node scripts/release-notes.mjs v1.1.0. A automação cria a GitHub Release quando uma tag compatível é enviada após revisão e testes.
