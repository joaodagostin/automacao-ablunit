<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="iso-8859-1">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" type="text/css" href="/sistema/pghtml/templates/font-awesome/css/all.min.css">
    <link rel="stylesheet" type="text/css" href="/sistema/jquery/jquery-confirm.min.css">
    <script src="/sistema/jquery/jquery-3.3.1.min.js"></script>
    <script src="/sistema/jquery/jquery-confirm.min.js"></script>
    <!-- BEGIN BLOCK_VERSAO -->
    <link rel="stylesheet" type="text/css" href="/sistema/templates/wtcc001c1.css?vdata=[data]">
    <script src="/sistema/templates/wtpl_funcs.js?vdata=[data]"></script>
    <script defer src="/sistema/templates/wtcc001c1.js?vdata=[data]"></script>
    <!-- END BLOCK_VERSAO -->
    <title>Laboratório ABLUnit</title>
</head>
<body>
    <div id="areaLoad" role="status" aria-label="Carregando"></div>
    <main class="container">
        <div class="area-titulo"><div class="box-titulo">LABORATÓRIO DE REGRESSÃO - ABLUNIT</div></div>
        <div class="area-sub-titulo">
            <span id="ambiente-resumo">Consultando ambiente...</span>
            <div class="area-botoes"><button class="botao bt-neutro" id="bt-atualizar" type="button"><i class="fa fa-sync-alt" aria-hidden="true"></i>Atualizar</button></div>
        </div>
        <div id="aviso" class="aviso" role="status" hidden></div>
        <nav class="abas" aria-label="Cadastros e resultados">
            <button class="aba selecionada" data-aba="baterias" type="button">Baterias</button>
            <button class="aba" data-aba="cenarios" type="button">Cenários</button>
            <button class="aba" data-aba="execucoes" type="button">Execuções e resultados</button>
            <button class="aba" data-aba="ambiente" type="button">Ambiente</button>
        </nav>

        <section id="aba-baterias" class="conteudo-aba split-view-container">
            <div class="painel-lado lista-cadastro">
                <div class="area-filtro"><strong>Baterias cadastradas</strong><button class="botao bt-neutro" id="bt-nova-bateria" type="button"><i class="fa fa-plus" aria-hidden="true"></i>Nova</button></div>
                <div class="container-scroll-dados"><table><thead><tr><th>Código</th><th>Descrição</th><th>Tipo</th></tr></thead><tbody id="lista-baterias"></tbody></table></div>
                <div class="container-resumo-fixo" id="resumo-baterias">0 baterias</div>
            </div>
            <div class="painel-lado formulario-cadastro">
                <div class="area-filtro"><strong>Cadastro de bateria</strong></div>
                <form id="form-bateria" class="formulario container-scroll-dados">
                    <div class="linha"><div class="material-textfield codigo"><input id="b-id" readonly value="0" placeholder=" "><label class="label" for="b-id">Código</label></div><div class="material-textfield"><input id="b-descricao" maxlength="120" required placeholder=" "><label class="label" for="b-descricao">Descrição *</label></div></div>
                    <div class="linha"><div class="select"><select class="select-text" id="b-tipo"><option value="CENARIOS">Cenários cadastrados na tela</option><option value="ABLUNIT">Classe ABLUnit existente</option></select><label class="select-label" for="b-tipo">Tipo *</label></div></div>
                    <div id="b-grupo-classe" class="linha"><div class="select"><select class="select-text" id="b-classe"></select><label class="select-label" for="b-classe">Classe da regra de negócio *</label></div></div>
                    <div id="b-grupo-teste" class="linha" hidden><div class="select"><select class="select-text" id="b-teste"></select><label class="select-label" for="b-teste">Classe de testes ABLUnit *</label></div><div class="material-textfield codigo"><input id="b-esperados" type="number" min="1" max="20000" value="10" placeholder=" "><label class="label" for="b-esperados">Casos esperados</label></div></div>
                    <p class="ajuda">Cadastre os valores de entrada e o resultado esperado em Cenários. Para testar outros métodos ou fontes .p, selecione uma classe ABLUnit registrada no servidor.</p>
                    <div class="linha area-botoes"><button class="botao bt-limpar" id="bt-excluir-bateria" type="button"><i class="fa fa-trash" aria-hidden="true"></i>Excluir</button><button class="botao bt-confirma" type="submit"><i class="fa fa-check" aria-hidden="true"></i>Confirmar</button></div>
                </form>
                <div class="container-resumo-fixo exec-toolbar"><div class="select pequena"><select class="select-text" id="b-repeticoes"><option value="1">1 execução</option></select><label class="select-label" for="b-repeticoes">Rodada</label></div><div class="select fonte-anexo"><select class="select-text" id="b-fonte"></select><label class="select-label" for="b-fonte">Fonte usado na execução</label></div><input type="file" id="arquivo-fonte" accept=".cls,.p" hidden><button class="botao bt-neutro" id="bt-anexar" type="button"><i class="fa fa-paperclip" aria-hidden="true"></i>Anexar fonte</button><button class="botao bt-limpar" id="bt-excluir-anexo" type="button">Excluir anexo</button><button class="botao bt-neutro" id="bt-fonte" type="button">Ver fonte de teste</button><button class="botao bt-confirma" id="bt-executar" type="button"><i class="fa fa-play" aria-hidden="true"></i>Executar bateria</button></div>
            </div>
        </section>

        <section id="aba-cenarios" class="conteudo-aba split-view-container" hidden>
            <div class="painel-lado lista-cadastro">
                <div class="area-filtro"><div class="select"><select class="select-text" id="c-filtro-bateria"></select><label class="select-label" for="c-filtro-bateria">Bateria</label></div><button class="botao bt-neutro" id="bt-novo-cenario" type="button">Novo</button></div>
                <div class="container-scroll-dados"><table><thead><tr><th>Código</th><th>Descrição</th><th>Modelo</th><th>Ativo</th></tr></thead><tbody id="lista-cenarios"></tbody></table></div>
                <div class="container-resumo-fixo" id="resumo-cenarios">0 cenários</div>
            </div>
            <div class="painel-lado formulario-cadastro">
                <div class="area-filtro"><strong>Entradas e resultado esperado</strong></div>
                <form id="form-cenario" class="formulario container-scroll-dados">
                    <div class="linha"><div class="material-textfield codigo"><input id="c-id" readonly value="0" placeholder=" "><label class="label" for="c-id">Código</label></div><div class="material-textfield"><input id="c-descricao" maxlength="120" required placeholder=" "><label class="label" for="c-descricao">Descrição *</label></div></div>
                    <div class="linha"><div class="select"><select class="select-text" id="c-bateria"></select><label class="select-label" for="c-bateria">Bateria *</label></div><div class="select"><select class="select-text" id="c-modelo"></select><label class="select-label" for="c-modelo">Método / modelo *</label></div></div>
                    <div id="c-addWhere"><div class="material-textfield campo-texto"><textarea id="c-where" rows="3" maxlength="8000" placeholder=" "></textarea><label class="label" for="c-where">Condição atual</label></div><div class="material-textfield campo-texto"><textarea id="c-condicao" rows="3" maxlength="8000" placeholder=" "></textarea><label class="label" for="c-condicao">Nova condição</label></div></div>
                    <div id="c-setErro" hidden><div class="material-textfield campo-texto"><textarea id="c-mensagens" rows="5" maxlength="16000" placeholder=" "></textarea><label class="label" for="c-mensagens">Mensagens: uma chamada setErro por linha</label></div></div>
                    <div id="c-metodo" hidden><div class="linha"><div class="select"><select class="select-text" id="c-metodo-nome"></select><label class="select-label" for="c-metodo-nome">Método da classe *</label></div></div><div id="c-argumentos"></div><p class="ajuda" id="c-metodo-ajuda"></p></div>
                    <div class="material-textfield campo-texto"><textarea id="c-esperado" rows="3" maxlength="8000" placeholder=" "></textarea><label class="label" for="c-esperado">Resultado esperado, inclusive espaços</label></div>
                    <label class="checkbox"><input type="checkbox" id="c-ativo" checked> Cenário ativo na execução</label>
                    <p class="ajuda">O esperado será comparado pelo Assert do ABLUnit com o retorno do método real.</p>
                    <div class="linha area-botoes"><button class="botao bt-limpar" id="bt-excluir-cenario" type="button">Excluir</button><button class="botao bt-confirma" type="submit"><i class="fa fa-check" aria-hidden="true"></i>Confirmar</button></div>
                </form>
            </div>
        </section>

        <section id="aba-execucoes" class="conteudo-aba split-view-container" hidden>
            <div class="painel-lado lista-cadastro">
                <div class="area-filtro"><strong>Histórico de execuções</strong></div>
                <div class="container-scroll-dados"><table><thead><tr><th>Bateria / data</th><th>Situação</th></tr></thead><tbody id="lista-execucoes"></tbody></table></div>
                <div class="container-resumo-fixo">Atualização automática durante a execução</div>
            </div>
            <div class="painel-lado resultados">
                <div class="area-filtro"><strong id="r-titulo">Selecione uma execução</strong><div class="area-botoes"><button class="botao bt-neutro" id="bt-logs" type="button">Logs</button><button class="botao bt-neutro" id="bt-csv" type="button">Exportar CSV</button></div></div>
                <div class="metricas"><div><span>Testes</span><strong id="r-total">-</strong></div><div><span>Aprovados</span><strong id="r-aprovados">-</strong></div><div><span>Falhas</span><strong id="r-falhas">-</strong></div><div><span>Erros</span><strong id="r-erros">-</strong></div><div><span>Ignorados</span><strong id="r-ignorados">-</strong></div></div>
                <div class="area-filtro"><div class="select pequena"><select class="select-text" id="r-repeticao"></select><label class="select-label" for="r-repeticao">Rodada</label></div><span id="r-tempo">Aguardando resultados</span></div>
                <div id="r-problemas" class="problemas" hidden></div>
                <div class="container-scroll-dados"><table class="tabela-resultados"><thead><tr><th>Caso / classe</th><th>Resultado</th><th>Tempo (s)</th><th>Mensagem</th></tr></thead><tbody id="lista-resultados"></tbody></table></div>
                <div class="container-resumo-fixo" id="r-resumo">Resultados provenientes de results.xml do ABLUnit</div>
            </div>
        </section>

        <section id="aba-ambiente" class="conteudo-aba" hidden>
            <div class="painel-lado"><div class="area-filtro"><strong>Configuração do Progress no servidor</strong></div><div class="formulario container-scroll-dados"><table class="tabela-ambiente"><tbody id="lista-ambiente"></tbody></table><p class="ajuda">Configuração em /opt/ablunitlab/app/wtcc001.json. Compatibilidade alvo: OpenEdge 12.2.16. A AVM filha usa seu próprio .pf; a conexão do agente web não é transferida para os testes.</p><p class="ajuda">Cadastros, entradas da rodada, XML, métricas e logs ficam diretamente em /opt/ablunitlab/trabalho/. Esta versão executa uma rodada por solicitação; os fontes de negócio usados são os instalados no PROPATH.</p></div></div>
        </section>
        <footer>ABLUnit · Cadastro de cenários e evidências de regressão</footer>
    </main>
    <dialog id="dialogo"><div class="area-filtro"><strong id="dialogo-titulo"></strong><button id="bt-fechar-dialogo" class="botao bt-neutro" type="button">Fechar</button></div><pre id="dialogo-texto"></pre><div class="area-botoes"><button id="bt-baixar-fonte" class="botao bt-confirma" type="button" hidden>Baixar .cls</button></div></dialog>
</body>
</html>
