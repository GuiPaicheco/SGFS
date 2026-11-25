# Alterações do SGFS

## 25/11/2026 — Distribuição integrada em PostgreSQL

- Gateway Node.js coordena Auth, PostgREST, funções Deno e a API CNES.
- CI verifica a cadeia de migrações, os privilégios do Auth e a restauração em banco descartável.
- Servidor e Vercel usam o mesmo build estático com o SDK do navegador incluído no ZIP. A interface da Vercel aguarda o gateway HTTPS para liberar os fluxos com banco.

[Distribuição principal](https://github.com/GuiPaicheco/SGFS/commit/d400176) · [Build compartilhado](https://github.com/GuiPaicheco/SGFS/commit/157a3ae) · [Arquivos idênticos](https://github.com/GuiPaicheco/SGFS/commit/8ad7df5)

## 24/11/2026 — SGFS 1.1.0

- Calendário com visualização mensal, paginação e acesso direto aos lançamentos.
- Histórico de registros por profissional em Férias e Cadastros.
- Senha provisória por unidade com troca obrigatória no primeiro acesso.
- Termos de uso e aviso de privacidade por sessão, histórico de versões e aviso de novidades.

[Registro v1.1.0](https://github.com/GuiPaicheco/SGFS/tree/v1.1.0) · [Linha do tempo do projeto](docs/tcc/LINHA_DO_TEMPO.md)

## 23/10/2026 — Preparação do repositório público

- README e guias atuais de uso, arquitetura, desenvolvimento, operação e publicação reorganizados.
- Documentos anteriores identificados como referências históricas/técnicas.
- Orientações de contribuição, segurança e privacidade, modelos de issue/PR e configuração de exemplo.
- Checagem de arquivos internos e padrões conhecidos de segredos integrada ao CI.
- Configuração local do editor retirada do versionamento; backups e saídas continuam ignorados.
- Alternativa estática Netlify alinhada ao build atual, sem implantação nesse provedor.

## 23/10/2026 — Identidade e preparação da base

- Identidade SGFS — Sistema de Gestão de Funcionários da Saúde, preservando os nomes institucionais.
- Revisão visual de entrada, login, navegação, calendário e telas móveis.
- Limpeza operacional excepcional autorizada, preservando unidades e Administração.

Os registros detalhados de etapas anteriores ficam no histórico Git e nos documentos identificados em [docs/README.md](docs/README.md). Datas e verificações históricas não comprovam o estado atual de uma instalação.
