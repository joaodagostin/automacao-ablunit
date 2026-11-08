# Laboratório de regressão ABLUnit (OpenEdge 12.2)

Protótipo desenvolvido no Trabalho de Conclusão de Curso **"Automação de testes em sistemas legados desenvolvidos em Progress OpenEdge ABL: uma abordagem para identificação de falhas de regressão"** (Engenharia de Software, UniSATC, 2026).

A ferramenta permite que o desenvolvedor, por uma tela web, faça o seguinte:

1. Cadastre **baterias** e **cenários de teste**: método a chamar, argumentos e resultado esperado.
2. **Anexe** a versão do fonte que quer avaliar (por exemplo, a versão original e cada alteração controlada), identificada por SHA-256.
3. Solicite a execução: o servidor **gera uma classe de teste ABLUnit** a partir dos cenários e a executa com o driver oficial `ABLUnitCore.p`, em uma **AVM batch separada** da sessão web.
4. Consulte o resultado por caso (aprovado, falha de asserção ou inconclusivo), os logs e o tempo, e exporte um CSV.

> Este repositório contém apenas o código desenvolvido para o laboratório. Não inclui fontes, regras de negócio, configurações nem dados da empresa onde o experimento foi realizado. Os caminhos de servidor e os nomes de classe que aparecem no código são genéricos (`/opt/ablunitlab/...`, `clsexemplo`).

## Arquivos

| Arquivo | Papel |
|---|---|
| `wtcc001c1.p` | Programa WebSpeed da tela: carrega o template e atende às ações AJAX (`vpad_exec`) |
| `wtcc001c1.tpl` | Template HTML da tela |
| `wtcc001c1.js` | Interface: cadastros, anexo de fonte em partes, leitura das assinaturas públicas, execução, resultados e CSV |
| `wtcc001c1.css` | Estilos da tela |
| `wtcc001ln.cls` | Núcleo: cadastros em JSON, geração da classe de teste, disparo da AVM batch, leitura do `results.xml` e classificação dos resultados |
| `wtcc001runner.p` | Programa executado na AVM batch: valida o pedido, roda o `ABLUnitCore.p`, lê o XML e grava o resultado |
| `wtcc001.exemplo.json` | Exemplo de configuração |
| `wtcc001lab.exemplo.pf` | Modelo do arquivo de parâmetros da AVM de testes |

## Como funciona

```
Tela (tpl/js) --POST vpad_exec + vjson--> wtcc001c1.p --> wtcc001ln
  cadastros (JSON) -> gera wtcc001_g_<id>.cls (os valores dos cenários ficam em um snapshot JSON, não no código)
                   -> nohup + timeout -> _progres -b -pf <lab.pf> -p wtcc001runner.p -param CFG=<cfg.json>
wtcc001runner.p --> ABLUnitCore.p --> results.xml --> LerXml() --> <id>_resultado.json --> tela / CSV
```

- **Fonte anexado:** durante a execução, a versão anexada é copiada para o diretório de trabalho, que fica primeiro no PROPATH da AVM de teste, e é removida ao final. Assim o código instalado nunca é alterado, e cada relatório fica associado ao SHA-256 da versão avaliada.
- **Classificação dos resultados:**
  - falha de asserção (`OpenEdge.Core.AssertionFailedError`) = **FALHA**;
  - erro de compilação, conexão ou timeout, XML ausente ou quantidade de testes divergente = **INCONCLUSIVO**;
  - nunca se aprova uma execução sem XML ou com testes ignorados.
- **Comparação:** o texto é comparado de forma exata (`COMPARE ... "RAW"` e tamanho). Números e datas são convertidos a partir do JSON, e `?` representa o valor desconhecido.
- **Concorrência:** um lock em arquivo permite uma execução por vez, e os cadastros têm controle de revisão.

## Requisitos

- OpenEdge **12.2** (desenvolvido e usado na 12.2.16) em Linux, com `OS-COMMAND` permitido no agente e `nohup`, `timeout`, `/bin/sh`, `ln`, `date`, `mv`, `cat` e `rm` disponíveis.
- **ABLUnit** no PROPATH da AVM de testes (`ablunit.pl` e `OpenEdge.Core.pl` do `$DLC`). A biblioteca da Progress **não** é distribuída aqui.
- A tela depende do framework web do sistema hospedeiro, que **não faz parte deste repositório**:
  - os includes `webpro.i` e `wpadfunc.i`;
  - a classe `Template`;
  - as variáveis de sessão `semp-empresa`, `suni-unidade` e `vusu-usuario`;
  - o script `wtpl_funcs.js` e os recursos em `/sistema/...`.

  Para usar em outro ambiente, adapte essas dependências.

## Configuração

1. Ajuste os caminhos fixos no código para o seu servidor:
   - `/opt/ablunitlab/app`: fontes e configuração;
   - `/opt/ablunitlab/trabalho`: cadastros, XML e logs;
   - `/opt/ablunitlab/templates`: template da tela.

   Os pontos a alterar estão em `wtcc001c1.p`, `wtcc001ln.cls`, `wtcc001runner.p` e em mensagens do `wtcc001c1.js`.
2. Copie `wtcc001.exemplo.json` para `wtcc001.json` e ajuste `dlc`, `avm`, `laboratory_pf`, `framework_propath`, `allowed_business_classes` e `allowed_test_classes`. Mantenha `execution_enabled` como `false` até configurar o `.pf`.
3. Copie `wtcc001lab.exemplo.pf` para o seu `.pf` de laboratório, com as conexões dos **bancos de teste**. Nunca use bancos de produção, porque os métodos chamados são executados de verdade.
4. Compile `wtcc001ln.cls`, `wtcc001runner.p` e `wtcc001c1.p` na mesma versão do OpenEdge da AVM de testes e publique a tela pelo mecanismo do sistema hospedeiro.

Os fontes ABL, o TPL e o JS estão em **ISO-8859-1** com quebras de linha CRLF. O `.gitattributes` evita conversões automáticas.

## Cuidados

- O modelo "Chamar método" executa o método real nos bancos do `.pf`. Use apenas métodos sem efeito colateral, ou bancos de laboratório descartáveis.
- A validação da requisição na tela é simples (marcador no POST). Não exponha a tela fora de uma rede interna sem reforçar a autenticação e a verificação de origem.

## Licença

Nenhuma licença foi definida até o momento. Todos os direitos são reservados ao autor.
