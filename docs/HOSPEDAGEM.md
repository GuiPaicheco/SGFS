# Hospedagem do SGFS

## Servidor PostgreSQL

Baixe o ZIP do GitHub, extraia no servidor e siga o [guia de implantação](../local/IMPLANTACAO.md). O gateway Node.js serve a aplicação e encaminha as chamadas de sessão, banco, funções e CNES.

## Vercel

O projeto sgfsbetim publica o mesmo build da interface usada no servidor. A Vercel encaminha sessões, dados e CNES para o gateway SGFS. PostgreSQL, Auth, PostgREST e Deno executam no servidor descrito no guia. O deploy da interface não provisiona contas.

- No projeto Vercel, configure `SGFS_GATEWAY_URL` com a URL HTTPS do gateway, incluindo o caminho e a barra final.
- Configure `SGFS_MUNICIPAL_PUBLIC_KEY` com a chave pública `anon` gerada pelo gateway. Após iniciar o servidor, ela pode ser obtida no arquivo servido em `assets/sgfs-config.js`.
- No servidor, adicione o domínio público da Vercel com barra final em `SGFS_RECOVERY_URLS` e reinicie o gateway. Isso autoriza o retorno de recuperação de senha ao endereço público.
- Defina as duas variáveis na Vercel e gere um novo deploy. Sem as duas configurações, a página exibe manutenção e os fluxos dependentes do banco permanecem indisponíveis.

## Conferência após publicação

Confira a versão e a disponibilidade do gateway. Valide login, recuperação, isolamento por unidade, calendário e exportações em ambiente isolado com dados fictícios. Consulte [publicação](PUBLICACAO.md).
