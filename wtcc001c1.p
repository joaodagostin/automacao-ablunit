/*------------------------------ T C C   A B L U N I T -------------------------------
 Programa: wtcc001c1.p  |  Laboratorio de regressao ABLUnit
 Padrao de tela: Template + vpad_exec + AJAX.
 Nenhuma regra de negocio e executada nesta sessao web.
----------------------------------------------------------------------------*/
ROUTINE-LEVEL ON ERROR UNDO, THROW.
USING Progress.Json.ObjectModel.*.
{webpro.i}
{wpadfunc.i}

/* Ajustar estes dois caminhos na instalacao, se necessario. */
DEFINE VARIABLE vconfig      AS CHARACTER NO-UNDO INITIAL "/opt/ablunitlab/app/wtcc001.json".
DEFINE VARIABLE vtemplate    AS CHARACTER NO-UNDO INITIAL "/opt/ablunitlab/templates/wtcc001c1.tpl".

DEFINE VARIABLE oLaboratorio AS CLASS wtcc001ln NO-UNDO.
DEFINE VARIABLE parser       AS ObjectModelParser NO-UNDO.
DEFINE VARIABLE entrada      AS JsonObject NO-UNDO.
DEFINE VARIABLE resposta     AS JsonObject NO-UNDO.
DEFINE VARIABLE dados        AS JsonObject NO-UNDO.
DEFINE VARIABLE vtpl         AS CLASS Template NO-UNDO.
DEFINE VARIABLE vpad-html    AS LONGCHAR NO-UNDO.
DEFINE VARIABLE vjson        AS LONGCHAR NO-UNDO.
DEFINE VARIABLE acao         AS CHARACTER NO-UNDO.
DEFINE VARIABLE postado      AS CHARACTER NO-UNDO.
DEFINE VARIABLE i            AS INTEGER NO-UNDO.

acao = get-value("vpad_exec").

IF acao <> "" THEN DO:
    DO ON ERROR UNDO, THROW:
        RUN p_validar_requisicao.

        ASSIGN oLaboratorio = NEW wtcc001ln(vconfig,
                                            semp-empresa,
                                            suni-unidade,
                                            STRING(vusu-usuario)).

        postado = get-value("vjson").

        IF postado = "" OR LENGTH(postado) > 30000 THEN
            wtcc001ln:Erro("Dados da requisicao invalidos ou muito grandes.").

        parser = NEW ObjectModelParser().
        entrada = CAST(parser:Parse(postado), JsonObject).

        /* Lista fechada: nunca RUN VALUE de procedimento informado pelo navegador. */
        CASE acao:
            WHEN "p_ambiente"       THEN dados = oLaboratorio:Ambiente().
            WHEN "p_listar"         THEN dados = oLaboratorio:Listar().
            WHEN "p_gravar_bateria" THEN dados = oLaboratorio:GravarBateria(entrada).
            WHEN "p_gravar_cenario" THEN dados = oLaboratorio:GravarCenario(entrada).
            WHEN "p_excluir"        THEN dados = oLaboratorio:Excluir(entrada).
            WHEN "p_fonte"          THEN dados = oLaboratorio:Fonte(entrada).
            WHEN "p_executar"       THEN dados = oLaboratorio:Iniciar(entrada).
            WHEN "p_resultado"      THEN dados = oLaboratorio:Resultado(entrada:GetCharacter("id")).
            WHEN "p_logs"           THEN dados = oLaboratorio:Logs(entrada).
            WHEN "p_anexo_parte"    THEN dados = oLaboratorio:AnexoParte(entrada).
            WHEN "p_anexo_excluir"  THEN dados = oLaboratorio:ExcluirAnexo(entrada).
            OTHERWISE wtcc001ln:Erro("Acao nao permitida.").
        END CASE.

        resposta = NEW JsonObject().
        resposta:Add("status", 0).
        resposta:Add("data", dados).

        CATCH erro AS Progress.Lang.Error:
            resposta = NEW JsonObject().
            resposta:Add("status", 1).
            resposta:Add("msg", erro:GetMessage(1)).
        END CATCH.

        FINALLY:
            IF VALID-OBJECT(oLaboratorio) THEN DELETE OBJECT oLaboratorio.
            IF VALID-OBJECT(parser) THEN DELETE OBJECT parser.
        END FINALLY.
    END.

    resposta:Write(vjson, FALSE).

    DO i = 1 TO LENGTH(vjson) BY 30000:
        {&out} STRING(SUBSTRING(vjson, i, 30000)).
    END.

    DELETE OBJECT resposta.
    IF VALID-OBJECT(entrada) THEN DELETE OBJECT entrada.
    IF VALID-OBJECT(dados) THEN DELETE OBJECT dados.

    RETURN.
END.

RUN p_load_html.
RUN p_replace_html.
RUN p_show_html.

IF VALID-OBJECT(vtpl) THEN DELETE OBJECT vtpl.

/* Validacao HTTP no WebSpeed, usando WEB-CONTEXT. */
PROCEDURE p_validar_requisicao:
    DEFINE VARIABLE cMarcador  AS CHARACTER NO-UNDO.

    /* O messenger pode nao repassar cabecalhos HTTP personalizados.
       Nesse caso o marcador acompanha o formulario POST. A validacao
       de origem abaixo permanece obrigatoria. */
    cMarcador = get-value("tcc_request").
    IF cMarcador <> "1" THEN
        UNDO, THROW NEW Progress.Lang.AppError("Marcador da consulta ausente ou invalido. Publique o novo wtcc001c1.js e recarregue com Ctrl+F5.", 9001).
END PROCEDURE.

PROCEDURE p_load_html:
    COPY-LOB FROM FILE vtemplate TO vpad-html
        CONVERT SOURCE CODEPAGE "ISO8859-1".
    vtpl = NEW Template(vpad-html).
END PROCEDURE.

PROCEDURE p_replace_html:
    vtpl:troca("[data]", STRING(TODAY, "99999999") + STRING(TIME)).
    vtpl:block("BLOCK_VERSAO").
END PROCEDURE.

PROCEDURE p_show_html:
    vtpl:show().
END PROCEDURE.
