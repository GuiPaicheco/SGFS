# Hospedagem do SGFS

## Servidor PostgreSQL

Baixe o ZIP do GitHub, extraia no servidor e siga o [guia de implantação](../local/IMPLANTACAO.md). O gateway Node.js serve a aplicação e encaminha as chamadas de sessão, banco, funções e CNES.

## Vercel

O projeto [sgfsbetim](https://sgfsbetim.vercel.app/) usa temporariamente o Supabase GeraFerias para Auth, PostgreSQL e Edge Functions. A Vercel encaminha as rotas `/backend/` ao projeto e executa a API CNES em `/api/cnes`. O endereço anterior redireciona para o novo. O Supabase gerencia as contas.

- Configure `SGFS_MUNICIPAL_PUBLIC_KEY` com a chave publicável do projeto Supabase.
- Configure `SUPABASE_URL` para a API CNES. Ao trocar de projeto, atualize também os destinos de `rewrites` em `vercel.json`.
- Para habilitar a recuperação de senha, inclua o endereço público na lista de redirecionamentos do Supabase Auth.
- As prévias sem chave publicável exibem a página de manutenção. Configure uma chave de prévia apenas para a branch que será validada.

## Conferência após publicação

Confira a versão e a disponibilidade do gateway. Valide login, recuperação, isolamento por unidade, calendário e exportações em ambiente isolado com dados fictícios. Consulte [publicação](PUBLICACAO.md).
