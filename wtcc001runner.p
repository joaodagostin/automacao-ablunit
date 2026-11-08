/* AVM batch dedicada. Alvo: OpenEdge Release 12.2.16.
   SESSION:PARAMETER e repassado ao driver nativo ABLUnitCore.p. */
ROUTINE-LEVEL ON ERROR UNDO, THROW.
USING Progress.Json.ObjectModel.*.
DEFINE VARIABLE arquivo AS CHARACTER NO-UNDO.
DEFINE VARIABLE prefixo AS CHARACTER NO-UNDO.
DEFINE VARIABLE id AS CHARACTER NO-UNDO.
DEFINE VARIABLE meta AS JsonObject NO-UNDO.
DEFINE VARIABLE resultado AS JsonObject NO-UNDO.
DEFINE VARIABLE leitor AS wtcc001ln NO-UNDO.
DEFINE VARIABLE i AS INTEGER NO-UNDO.
DEFINE VARIABLE texto AS CHARACTER NO-UNDO.
DEFINE VARIABLE erroDriver AS CHARACTER NO-UNDO.
DEFINE VARIABLE trabalho AS CHARACTER NO-UNDO INITIAL "/opt/ablunitlab/trabalho".

DO ON ERROR UNDO, THROW:
    IF NOT SESSION:PARAMETER BEGINS "CFG=" THEN wtcc001ln:Erro("Parametro CFG ausente.").
    arquivo = SUBSTRING(SESSION:PARAMETER, 5).
    id = SUBSTRING(arquivo, LENGTH(trabalho + "/wtcc001_e_") + 1, 32).
    IF LENGTH(id) <> 32 THEN wtcc001ln:Erro("Identificador invalido.").
    DO i = 1 TO LENGTH(id):
        IF INDEX("0123456789abcdef", SUBSTRING(id, i, 1)) = 0 THEN wtcc001ln:Erro("Identificador invalido.").
    END.
    IF arquivo <> trabalho + "/wtcc001_e_" + id + "_cfg.json" THEN wtcc001ln:Erro("Caminho CFG invalido.").
    prefixo = trabalho + "/wtcc001_e_" + id.
    meta = wtcc001ln:Ler(prefixo + "_meta.json").
    IF NOT PROVERSION(1) BEGINS "12.2.16" THEN wtcc001ln:Erro("Este pacote foi preparado para OpenEdge 12.2.16. AVM atual: " + PROVERSION(1)).
    IF SEARCH("ABLUnitCore.r") = ? AND SEARCH("ABLUnitCore.p") = ? THEN
        wtcc001ln:Erro("ABLUnitCore.r/.p nao encontrado no PROPATH da AVM batch: " + PROPATH).
    IF wtcc001ln:Existe(trabalho + "/results.xml") THEN wtcc001ln:Erro("results.xml ja existe; nao sera sobrescrito.").
    leitor = NEW wtcc001ln("/opt/ablunitlab/app/wtcc001.json", meta:GetInteger("empresa"), meta:GetInteger("unidade"), meta:GetCharacter("usuario")).
    DO ON ERROR UNDO, THROW:
        RUN ABLUnitCore.p.
        CATCH erroCore AS Progress.Lang.Error:
            DO i = 1 TO erroCore:NumMessages:
                erroDriver = SUBSTRING(erroDriver + erroCore:GetMessage(i) + CHR(10), 1, 12000).
            END.
        END CATCH.
    END.
    IF NOT wtcc001ln:Existe(trabalho + "/results.xml") THEN wtcc001ln:Erro("ABLUnit nao produziu results.xml. " + erroDriver).
    OS-RENAME VALUE(trabalho + "/results.xml") VALUE(prefixo + "_results.xml").
    IF OS-ERROR <> 0 THEN wtcc001ln:Erro("Nao foi possivel renomear results.xml.").
    resultado = leitor:LerXml(prefixo + "_results.xml", meta:GetInteger("esperados")).
    IF erroDriver <> "" THEN DO:
        resultado:Set("status", "ERRO").
        resultado:Add("mensagem", "Driver ABLUnit retornou erro: " + erroDriver).
    END.
    resultado:Add("proversion", PROVERSION(1)).
    resultado:Add("cpinternal", SESSION:CPINTERNAL).
    wtcc001ln:Gravar(prefixo + "_resultado.json", resultado).
    CATCH erro AS Progress.Lang.Error:
        resultado = NEW JsonObject().
        resultado:Add("status", "ERRO").
        DO i = 1 TO erro:NumMessages:
            texto = SUBSTRING(texto + erro:GetMessage(i) + CHR(10), 1, 12000).
        END.
        resultado:Add("mensagem", texto).
        resultado:Add("proversion", PROVERSION(1)).
        IF prefixo <> "" THEN wtcc001ln:Gravar(prefixo + "_resultado.json", resultado).
    END CATCH.
    FINALLY:
        IF VALID-OBJECT(leitor) THEN DELETE OBJECT leitor.
        IF VALID-OBJECT(meta) THEN DELETE OBJECT meta.
        IF VALID-OBJECT(resultado) THEN DELETE OBJECT resultado.
    END FINALLY.
END.
/* Encerra exclusivamente a AVM filha, nunca a sessao WebSpeed. */
QUIT.
