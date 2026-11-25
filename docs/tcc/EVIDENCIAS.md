# Avaliação e evidências do SGFS

## Resultados técnicos já registrados

| Versão | O que foi verificado | Limite da evidência |
| --- | --- | --- |
| `15b687b` · 25/11/2026 | CI concluído com testes de aplicação, aplicação das migrações em banco vazio, ensaios transacionais e restauração de backup sintético. | Validação técnica executada em ambiente descartável. [Execução do GitHub Actions](https://github.com/GuiPaicheco/SGFS/actions/runs/45682844724) |
| `8ad7df5` · 25/11/2026 | Interface publicada. O SHA-256 de `app.js` e do SDK Supabase coincidiu entre a Vercel e a instância iniciada a partir do ZIP. Nessa instância, o Auth e uma consulta de calendário via PostgREST responderam. | Verificação de distribuição, inicialização e leitura. O fluxo autenticado pela Vercel depende do gateway HTTPS. [Commit](https://github.com/GuiPaicheco/SGFS/commit/8ad7df5) · [Deploy](https://vercel.com/guipaichecos-projects/sgfsbetim/A4vgvRV2bhJxDpvQjbGH6xnHc3Li) |

Os ensaios anteriores estão no [arquivo histórico](../historico/README.md). Cite a versão, o ambiente e o limite de cada resultado que usar no TCC.

## Casos propostos para o TCC

| Caso | Critério observável |
| --- | --- |
| Registrar, corrigir e cancelar um afastamento | Conferir datas, resultado no calendário, motivo, autoria e versões disponíveis na consulta de histórico. |
| Tentar operar em outra unidade | Conferir que uma conta RH de teste não lê nem altera dados fora do seu escopo. Registrar a resposta do servidor e a interface. |
| Atualizar um cadastro a partir de dados CNES fictícios | Comparar identificadores de vínculo e afastamentos antes e depois. Incluir uma coleta incompleta e uma repetição da mesma fonte. |
| Restaurar uma base sintética | Comparar registros, funções, privilégios e políticas de acesso. Repetir ao menos uma consulta e uma operação autorizada no destino. |

Os casos acima estão propostos. Defina o conjunto de entradas e a regra de aprovação antes de executá-los. Para medir tempo, erros de preenchimento ou facilidade de uso, fixe o procedimento de comparação e registre o tamanho da amostra e as limitações. Combine com a orientação acadêmica o procedimento aplicável caso a avaliação envolva pessoas.

## Modelo de registro

Preencha um registro por execução ou conjunto de casos, com os resultados falhos e os casos pendentes.

- **Identificação.** Data, versão ou commit, ambiente, ferramenta e versão da base sintética.
- **Caso.** Requisito avaliado, entradas, passos e resultado esperado.
- **Resultado.** Resultado observado, evidência verificável e situação: aprovado, reprovado ou não executado.
- **Limite.** Parte do fluxo que o teste cobre e verificações que ainda faltam.

O [roteiro de homologação](../GUIA_HOMOLOGACAO.md) tem casos adicionais para a avaliação institucional. Para evidência pública ou acadêmica, parta de dados fictícios e siga o [guia de privacidade](../PRIVACIDADE.md).
