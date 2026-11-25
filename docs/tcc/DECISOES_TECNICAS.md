# Decisões técnicas do SGFS

| Decisão | Motivo e consequência | Rastro no projeto |
| --- | --- | --- |
| Organizar o uso operacional por unidade | O RH precisa atuar no cadastro e calendário da unidade, com autoria registrada. A seleção de operador documenta uma identidade declarada dentro de uma conta institucional. A autorização é revalidada no servidor. | [Contas RH](https://github.com/GuiPaicheco/SGFS/commit/9b69f7d) · [Arquitetura](../ARQUITETURA.md) |
| Separar a fonte CNES dos registros do RH | Uma coleta pública pode chegar incompleta ou trazer dados diferentes. A Administração confere a incorporação, e os identificadores dos vínculos permanecem estáveis para preservar os lançamentos. | [Integração CNES](https://github.com/GuiPaicheco/SGFS/commit/54e034b) · [Atualização CNES](../ATUALIZACAO_CNES.md) |
| Versionar alterações no registro | Alterações de data e cancelamentos precisam manter o histórico do ato. A aplicação conserva versões e registra autoria e justificativa conforme a operação. | [Revisões](https://github.com/GuiPaicheco/SGFS/commit/89f568d) · [Operações](../GUIA_OPERACOES_FINAIS.md) |
| Usar um gateway para a distribuição em PostgreSQL | O navegador usa um endereço para a aplicação, o Auth, os dados e o CNES. O gateway coordena os serviços e verifica requisitos de sessão. A Vercel pode servir a interface com o mesmo build e encaminhar chamadas ao gateway HTTPS. | [Distribuição integrada](https://github.com/GuiPaicheco/SGFS/commit/d400176) · [Build compartilhado](https://github.com/GuiPaicheco/SGFS/commit/157a3ae) · [Hospedagem](../HOSPEDAGEM.md) |
| Ensaiar migração e restauração em banco descartável | A restauração precisa preservar dados, regras de acesso e estruturas da aplicação. O CI aplica as migrações e compara a restauração de uma base sintética. | [Restauração](https://github.com/GuiPaicheco/SGFS/commit/15b687b) · [Desenvolvimento](../DESENVOLVIMENTO.md) |

Nas próximas decisões, registre data, situação, problema, opções consideradas, escolha, consequência e fonte. Quando o Git registrar apenas a solução adotada, identifique como hipótese qualquer motivação que ainda precise ser confirmada.
