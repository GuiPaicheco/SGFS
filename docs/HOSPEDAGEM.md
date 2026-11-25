# Hospedagem do SGFS

## Distribuição PostgreSQL

Execute o gateway Node.js atrás do proxy HTTPS institucional. O gateway serve a interface e encaminha as chamadas de sessão, banco, funções de aplicação e CNES. Use PostgreSQL dedicado à aplicação e mantenha Auth, PostgREST, Deno e Uvicorn acessíveis apenas em loopback. Consulte [implantação integrada](../local/IMPLANTACAO.md).

A geração da interface não provisiona contas nem modifica o banco. Aplique as migrações no ambiente autorizado e confira as políticas RLS antes de abrir o serviço.

## Instalação anterior

O site anterior da Vercel exibe o aviso de manutenção. A configuração da distribuição integrada desativa o deploy automático da branch `main` na Vercel e o build de produção na Netlify. A configuração anterior e o aviso estão registrados no commit `0fa84f6`.

## Conferência após publicação

Confirme a versão e a disponibilidade do gateway. Valide login, recuperação, isolamento por unidade, calendário e exportações com contas autorizadas e dados fictícios. Consulte [publicação](PUBLICACAO.md).
