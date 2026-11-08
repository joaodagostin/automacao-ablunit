/* Laboratorio ABLUnit simples - alvo OpenEdge 12.2.16. */
ROUTINE-LEVEL ON ERROR UNDO, THROW.
USING Progress.Json.ObjectModel.*.
CLASS wtcc001ln:
    DEFINE PRIVATE VARIABLE vempresa AS INTEGER NO-UNDO.
    DEFINE PRIVATE VARIABLE vunidade AS INTEGER NO-UNDO.
    DEFINE PRIVATE VARIABLE cfg AS JsonObject NO-UNDO.
    DEFINE PRIVATE VARIABLE base AS CHARACTER NO-UNDO.
    DEFINE PRIVATE VARIABLE trabalho AS CHARACTER NO-UNDO.
    DEFINE PRIVATE VARIABLE usuario AS CHARACTER NO-UNDO.
    DEFINE PRIVATE VARIABLE cadastro AS CHARACTER NO-UNDO.
    DEFINE PRIVATE VARIABLE lockCadastro AS CHARACTER NO-UNDO.
    DEFINE PRIVATE VARIABLE lockExecucao AS CHARACTER NO-UNDO.
    DEFINE PRIVATE VARIABLE anexosArq AS CHARACTER NO-UNDO.
    DEFINE PRIVATE VARIABLE lockAnexos AS CHARACTER NO-UNDO.
    DEFINE PRIVATE VARIABLE casos AS JsonArray NO-UNDO.
    DEFINE PRIVATE VARIABLE problemas AS JsonArray NO-UNDO.
    DEFINE PRIVATE VARIABLE aprovados AS INTEGER NO-UNDO.
    DEFINE PRIVATE VARIABLE falhas AS INTEGER NO-UNDO.
    DEFINE PRIVATE VARIABLE erros AS INTEGER NO-UNDO.
    DEFINE PRIVATE VARIABLE ignorados AS INTEGER NO-UNDO.
    DEFINE PRIVATE VARIABLE somaTempo AS DECIMAL NO-UNDO.
    DEFINE PRIVATE VARIABLE tempos AS INTEGER NO-UNDO.
    DEFINE PRIVATE TEMP-TABLE ttIdentidade NO-UNDO
        FIELD chave AS CHARACTER CASE-SENSITIVE
        INDEX primaria IS PRIMARY UNIQUE chave.

/* Arquivos: todos planos em /opt/ablunitlab/app/. */

    METHOD PUBLIC STATIC VOID Erro(INPUT p AS CHARACTER):
        UNDO, THROW NEW Progress.Lang.AppError(p, 9001).
    END METHOD.

    METHOD PUBLIC STATIC CHARACTER Id():
        RETURN LC(REPLACE(GUID(GENERATE-UUID), "-", "")).
    END METHOD.

    METHOD PUBLIC STATIC LOGICAL Existe(INPUT p AS CHARACTER):
        FILE-INFO:FILE-NAME = p.
        RETURN FILE-INFO:FULL-PATHNAME <> ?.
    END METHOD.

    METHOD PUBLIC STATIC CHARACTER Shell(INPUT p AS CHARACTER):

        /* ' -> '"'"' ; não usar aspas duplas para parâmetros de shell. */
        RETURN CHR(39) + REPLACE(p, CHR(39), CHR(39) + CHR(34) + CHR(39) + CHR(34) + CHR(39)) + CHR(39).
    END METHOD.

    METHOD PUBLIC STATIC CHARACTER Texto(INPUT p AS CHARACTER):
        DEFINE VARIABLE t AS LONGCHAR NO-UNDO.
        COPY-LOB FROM FILE p TO t.
        RETURN STRING(SUBSTRING(t, 1, 30000)).
    END METHOD.

    METHOD PUBLIC STATIC VOID GravarTexto(INPUT p AS CHARACTER, INPUT t AS LONGCHAR):
        COPY-LOB FROM t TO FILE p CONVERT TARGET CODEPAGE "ISO8859-1".
    END METHOD.

    METHOD PUBLIC STATIC JsonObject Ler(INPUT p AS CHARACTER):
        DEFINE VARIABLE parser AS ObjectModelParser NO-UNDO.
        DEFINE VARIABLE obj AS JsonObject NO-UNDO.
        parser = NEW ObjectModelParser().
        obj = CAST(parser:ParseFile(p), JsonObject).
        RETURN obj.
        FINALLY:
            IF VALID-OBJECT(parser) THEN DELETE OBJECT parser.
        END FINALLY.
    END METHOD.

    METHOD PUBLIC STATIC VOID Gravar(INPUT p AS CHARACTER, INPUT obj AS JsonObject):
        DEFINE VARIABLE temporario AS CHARACTER NO-UNDO.
        DEFINE VARIABLE e AS INTEGER NO-UNDO.
        DEFINE VARIABLE preservado AS CHARACTER NO-UNDO.
        temporario = p + "." + wtcc001ln:Id() + ".tmp".
        IF NOT obj:WriteFile(temporario, TRUE) THEN wtcc001ln:Erro("Falha ao gravar JSON.").
        IF wtcc001ln:Existe(p) THEN DO:
            OS-DELETE VALUE(p).
            e = OS-ERROR.
            IF e <> 0 THEN wtcc001ln:Erro("Falha ao substituir JSON (" + STRING(e) + "): " + p).
        END.
        OS-RENAME VALUE(temporario) VALUE(p).
        e = OS-ERROR.
        IF e <> 0 THEN DO:
            ASSIGN preservado = temporario
                   temporario = "".
            wtcc001ln:Erro("Falha ao publicar JSON (" + STRING(e) + "). Conteudo preservado em " + preservado).
        END.
        FINALLY:
            IF temporario <> "" AND wtcc001ln:Existe(temporario) THEN OS-DELETE VALUE(temporario).
        END FINALLY.
    END METHOD.

    METHOD PUBLIC STATIC LOGICAL Travar(INPUT p AS CHARACTER):
        DEFINE VARIABLE candidato AS CHARACTER NO-UNDO.
        DEFINE VARIABLE marca AS CHARACTER NO-UNDO.
        DEFINE VARIABLE comando AS CHARACTER NO-UNDO.
        candidato = p + "." + wtcc001ln:Id() + ".tmp".
        marca = candidato + ".status".
        wtcc001ln:GravarTexto(candidato, "LOCK").

        /* ln cria arquivo atomicamente; nenhum diretorio de lock e criado. */
        comando = "if /bin/ln " + wtcc001ln:Shell(candidato) + " " + wtcc001ln:Shell(p)
                + " 2>/dev/null; then echo SIM; else echo NAO; fi > " + wtcc001ln:Shell(marca).
        OS-COMMAND SILENT VALUE(comando).
        IF NOT wtcc001ln:Existe(marca) THEN wtcc001ln:Erro("Nao foi possivel obter o lock de arquivos.").
        RETURN TRIM(wtcc001ln:Texto(marca)) = "SIM".
        FINALLY:
            OS-DELETE VALUE(candidato) VALUE(marca).
        END FINALLY.
    END METHOD.

    METHOD PUBLIC STATIC VOID Destravar(INPUT p AS CHARACTER):
        OS-DELETE VALUE(p).
    END METHOD.

    /* Validacao de caracteres sem uso de VERIFY(), inexistente em ABL. */
    METHOD PRIVATE STATIC LOGICAL CaracteresValidos(INPUT texto AS CHARACTER,
                                                   INPUT aceitos AS CHARACTER):
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE j AS INTEGER NO-UNDO.
        DEFINE VARIABLE encontrou AS LOGICAL NO-UNDO.

        IF texto = ? OR aceitos = ? THEN RETURN FALSE.

        DO i = 1 TO LENGTH(texto):
            encontrou = FALSE.

            DO j = 1 TO LENGTH(aceitos):
                IF COMPARE(SUBSTRING(texto, i, 1), "EQ",
                           SUBSTRING(aceitos, j, 1), "RAW") THEN DO:
                    encontrou = TRUE.
                    LEAVE.
                END.
            END.

            IF NOT encontrou THEN RETURN FALSE.
        END.

        RETURN TRUE.
    END METHOD.

/* Cadastro e execucao. */

    CONSTRUCTOR PUBLIC wtcc001ln(INPUT arquivoConfig AS CHARACTER, INPUT empresa AS INTEGER, INPUT unidade AS INTEGER, INPUT pUsuario AS CHARACTER):
        DEFINE VARIABLE permitidos AS JsonArray NO-UNDO.
        DEFINE VARIABLE permitido AS LOGICAL NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        cfg = wtcc001ln:Ler(arquivoConfig).
        permitidos = cfg:GetJsonArray("allowed_users").
        permitido = permitidos:Length = 0 AND pUsuario <> "".
        DO i = 1 TO permitidos:Length:
            IF permitidos:GetCharacter(i) = pUsuario AND pUsuario <> "" THEN permitido = TRUE.
        END.
        IF NOT permitido THEN wtcc001ln:Erro("Usuario sem acesso ao laboratorio.").
        IF empresa <= 0 OR unidade < 0 THEN wtcc001ln:Erro("Empresa/unidade nao identificada.").
        ASSIGN base = "/opt/ablunitlab/app"
               trabalho = "/opt/ablunitlab/trabalho"
               usuario = pUsuario
               vempresa = empresa
               vunidade = unidade
               cadastro = trabalho + "/wtcc001_cad_" + STRING(empresa) + "_" + STRING(unidade) + ".json"
               lockCadastro = cadastro + ".lock"
               anexosArq = trabalho + "/wtcc001_anx_" + STRING(empresa) + "_" + STRING(unidade) + ".json"
               lockAnexos = anexosArq + ".lock"
               lockExecucao = trabalho + "/wtcc001_exec.lock".
    END CONSTRUCTOR.

    DESTRUCTOR PUBLIC wtcc001ln():
        IF VALID-OBJECT(cfg) THEN DELETE OBJECT cfg.
    END DESTRUCTOR.

    METHOD PRIVATE JsonObject Dados():
        DEFINE VARIABLE d AS JsonObject NO-UNDO.
        IF wtcc001ln:Existe(cadastro) THEN RETURN wtcc001ln:Ler(cadastro).
        d = NEW JsonObject().
        d:Add("revisao", 0).
        d:Add("baterias", NEW JsonArray()).
        d:Add("cenarios", NEW JsonArray()).
        d:Add("execucoes", NEW JsonArray()).
        RETURN d.
    END METHOD.

    METHOD PUBLIC VOID ValidarRequisicao(INPUT metodo AS CHARACTER, INPUT marcador AS CHARACTER, INPUT origem AS CHARACTER, INPUT referer AS CHARACTER, INPUT host AS CHARACTER):
        DEFINE VARIABLE autoridade AS CHARACTER NO-UNDO.
        DEFINE VARIABLE esperado AS CHARACTER NO-UNDO.
        IF metodo <> "POST" OR marcador <> "1" THEN wtcc001ln:Erro("Requisição inválida.").
        esperado = cfg:GetCharacter("web_origin").
        IF origem = "" THEN origem = referer.
        IF INDEX(origem, "://") = 0 THEN wtcc001ln:Erro("Origem da requisição não identificada.").
        autoridade = ENTRY(1, SUBSTRING(origem, INDEX(origem, "://") + 3), "/").
        IF esperado <> "" THEN DO:
            origem = ENTRY(1, origem, "/") + "//" + autoridade.
            IF origem <> esperado THEN wtcc001ln:Erro("Origem da requisição não permitida.").
        END.
        ELSE IF autoridade <> host OR host = "" THEN wtcc001ln:Erro("Origem da requisição não permitida.").
    END METHOD.

    METHOD PRIVATE VOID Revisao(INPUT d AS JsonObject, INPUT entrada AS JsonObject):
        IF d:GetInteger("revisao") <> entrada:GetInteger("revisao") THEN
            wtcc001ln:Erro("Outro usuário alterou os cadastros. Atualize a tela antes de salvar.").
    END METHOD.

    METHOD PRIVATE VOID Salvar(INPUT d AS JsonObject):
        d:Set("revisao", d:GetInteger("revisao") + 1).
        wtcc001ln:Gravar(cadastro, d).
    END METHOD.

    METHOD PRIVATE INTEGER Posicao(INPUT a AS JsonArray, INPUT id AS INTEGER):
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DO i = 1 TO a:Length:
            IF a:GetJsonObject(i):GetInteger("id") = id THEN RETURN i.
        END.
        RETURN 0.
    END METHOD.

    METHOD PRIVATE INTEGER Proximo(INPUT a AS JsonArray):
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE ultimo AS INTEGER NO-UNDO.
        DO i = 1 TO a:Length:
            ultimo = MAXIMUM(ultimo, a:GetJsonObject(i):GetInteger("id")).
        END.
        RETURN ultimo + 1.
    END METHOD.

    METHOD PRIVATE CHARACTER Permitido(INPUT chave AS CHARACTER, INPUT valor AS CHARACTER):
        DEFINE VARIABLE a AS JsonArray NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        a = cfg:GetJsonArray(chave).
        DO i = 1 TO a:Length:
            IF a:GetCharacter(i) = valor THEN RETURN a:GetCharacter(i).
        END.
        wtcc001ln:Erro("Classe não cadastrada na configuração do servidor: " + valor).
        RETURN "".
    END METHOD.

    METHOD PRIVATE CHARACTER ClassePermitida(INPUT valor AS CHARACTER):
        DEFINE VARIABLE a AS JsonArray NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        a = cfg:GetJsonArray("allowed_business_classes").
        DO i = 1 TO a:Length:
            IF a:GetCharacter(i) = valor THEN RETURN a:GetCharacter(i).
        END.
        a = Anexos():GetJsonArray("anexos").
        DO i = 1 TO a:Length:
            IF a:GetJsonObject(i):GetCharacter("nome") = valor + ".cls" THEN RETURN valor.
        END.
        wtcc001ln:Erro("Classe nao cadastrada em allowed_business_classes nem anexada: " + valor).
        RETURN "".
    END METHOD.

    METHOD PRIVATE VOID Descricao(INPUT t AS CHARACTER):
        IF t = ? OR TRIM(t) = "" OR LENGTH(t) > 120 THEN wtcc001ln:Erro("Informe descrição com até 120 caracteres.").
    END METHOD.

    METHOD PUBLIC JsonObject Listar():
        DEFINE VARIABLE d AS JsonObject NO-UNDO.
        DEFINE VARIABLE e AS JsonObject NO-UNDO.
        DEFINE VARIABLE lista AS JsonArray NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE detalhe AS JsonObject NO-UNDO.
        d = Dados().
        lista = d:GetJsonArray("execucoes").
        DO i = 1 TO lista:Length:
            e = lista:GetJsonObject(i).
            detalhe = Resultado(e:GetCharacter("id")).
            IF e:Has("status") THEN e:Set("status", detalhe:GetCharacter("status")).
            ELSE e:Add("status", detalhe:GetCharacter("status")).
        END.
        d:Add("ambiente", Ambiente()).
        d:Add("anexos", Anexos():GetJsonArray("anexos")).
        RETURN d.
    END METHOD.

    METHOD PUBLIC JsonObject Ambiente():
        DEFINE VARIABLE r AS JsonObject NO-UNDO.
        DEFINE VARIABLE classes AS JsonArray NO-UNDO.
        DEFINE VARIABLE a AS JsonArray NO-UNDO.
        DEFINE VARIABLE nomes AS CHARACTER NO-UNDO.
        DEFINE VARIABLE nome AS CHARACTER NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        classes = NEW JsonArray().
        a = cfg:GetJsonArray("allowed_business_classes").
        DO i = 1 TO a:Length:
            classes:Add(a:GetCharacter(i)).
            nomes = nomes + "," + a:GetCharacter(i).
        END.
        a = Anexos():GetJsonArray("anexos").
        DO i = 1 TO a:Length:
            nome = a:GetJsonObject(i):GetCharacter("nome").
            IF NUM-ENTRIES(nome, ".") = 2 AND ENTRY(2, nome, ".") = "cls" AND LOOKUP(ENTRY(1, nome, "."), nomes) = 0 THEN DO:
                classes:Add(ENTRY(1, nome, ".")).
                nomes = nomes + "," + ENTRY(1, nome, ".").
            END.
        END.
        r = NEW JsonObject().
        r:Add("nome", cfg:GetCharacter("environment_name")).
        r:Add("habilitado", cfg:GetLogical("execution_enabled")).
        r:Add("avm", cfg:GetCharacter("avm")).
        r:Add("pf", cfg:GetCharacter("laboratory_pf")).
        r:Add("projeto", base).
        r:Add("avm_existe", wtcc001ln:Existe(cfg:GetCharacter("avm"))).
        r:Add("pf_existe", wtcc001ln:Existe(cfg:GetCharacter("laboratory_pf"))).
        r:Add("launcher_existe", wtcc001ln:Existe(base + "/wtcc001runner.p")).
        r:Add("classes", classes).
        r:Add("testes", cfg:GetJsonArray("allowed_test_classes")).
        r:Add("proversion_agente", PROVERSION(1)).
        RETURN r.
    END METHOD.

    METHOD PUBLIC JsonObject GravarBateria(INPUT entrada AS JsonObject):
        DEFINE VARIABLE d AS JsonObject NO-UNDO.
        DEFINE VARIABLE a AS JsonArray NO-UNDO.
        DEFINE VARIABLE b AS JsonObject NO-UNDO.
        DEFINE VARIABLE id AS INTEGER NO-UNDO.
        DEFINE VARIABLE pos AS INTEGER NO-UNDO.
        DEFINE VARIABLE travado AS LOGICAL NO-UNDO.
        travado = wtcc001ln:Travar(lockCadastro).
        IF NOT travado THEN wtcc001ln:Erro("Cadastro em uso. Tente novamente.").
        d = Dados().
        Revisao(d, entrada).
        b = entrada:GetJsonObject("bateria").
        Descricao(b:GetCharacter("descricao")).
        a = d:GetJsonArray("baterias").
        id = b:GetInteger("id").
        IF id < 0 THEN wtcc001ln:Erro("Código inválido.").
        IF id = 0 THEN DO:
            IF a:Length >= 100 THEN wtcc001ln:Erro("Limite de 100 baterias.").
            b:Set("id", Proximo(a)).
        END.
        ELSE DO:
            pos = Posicao(a, id).
            IF pos = 0 THEN wtcc001ln:Erro("Bateria não encontrada.").
        END.
        CASE b:GetCharacter("tipo"):
            WHEN "CENARIOS" THEN b:Set("classe", ClassePermitida(b:GetCharacter("classe"))).
            WHEN "ABLUNIT" THEN DO:
                b:Set("teste", Permitido("allowed_test_classes", b:GetCharacter("teste"))).
                IF b:GetInteger("esperados") <= 0 OR b:GetInteger("esperados") > 20000 THEN
                    wtcc001ln:Erro("Informe a quantidade esperada de testes da classe ABLUnit.").
            END.
            OTHERWISE wtcc001ln:Erro("Tipo de bateria inválido.").
        END CASE.
        IF pos = 0 THEN a:Add(b).
        ELSE a:Set(pos, b).
        Salvar(d).
        RETURN d.
        FINALLY:
            IF travado THEN wtcc001ln:Destravar(lockCadastro).
        END FINALLY.
    END METHOD.

    METHOD PUBLIC JsonObject GravarCenario(INPUT entrada AS JsonObject):
        DEFINE VARIABLE d AS JsonObject NO-UNDO.
        DEFINE VARIABLE a AS JsonArray NO-UNDO.
        DEFINE VARIABLE b AS JsonArray NO-UNDO.
        DEFINE VARIABLE c AS JsonObject NO-UNDO.
        DEFINE VARIABLE id AS INTEGER NO-UNDO.
        DEFINE VARIABLE pos AS INTEGER NO-UNDO.
        DEFINE VARIABLE bateria AS INTEGER NO-UNDO.
        DEFINE VARIABLE travado AS LOGICAL NO-UNDO.
        travado = wtcc001ln:Travar(lockCadastro).
        IF NOT travado THEN wtcc001ln:Erro("Cadastro em uso. Tente novamente.").
        d = Dados().
        Revisao(d, entrada).
        c = entrada:GetJsonObject("cenario").
        Descricao(c:GetCharacter("descricao")).
        bateria = c:GetInteger("bateria_id").
        b = d:GetJsonArray("baterias").
        pos = Posicao(b, bateria).
        IF pos = 0 THEN wtcc001ln:Erro("Bateria não encontrada.").
        IF b:GetJsonObject(pos):GetCharacter("tipo") <> "CENARIOS" THEN wtcc001ln:Erro("A bateria usa classe ABLUnit pronta.").
        wtcc001ln:Validar(c).
        a = d:GetJsonArray("cenarios").
        id = c:GetInteger("id").
        pos = 0.
        IF id < 0 THEN wtcc001ln:Erro("Código inválido.").
        IF id = 0 THEN DO:
            IF a:Length >= 200 THEN wtcc001ln:Erro("Limite de 200 cenários cadastrados.").
            c:Set("id", Proximo(a)).
        END.
        ELSE DO:
            pos = Posicao(a, id).
            IF pos = 0 THEN wtcc001ln:Erro("Cenário não encontrado.").
        END.
        IF pos = 0 THEN a:Add(c).
        ELSE a:Set(pos, c).
        Salvar(d).
        RETURN d.
        FINALLY:
            IF travado THEN wtcc001ln:Destravar(lockCadastro).
        END FINALLY.
    END METHOD.

    METHOD PUBLIC JsonObject Excluir(INPUT entrada AS JsonObject):
        DEFINE VARIABLE d AS JsonObject NO-UNDO.
        DEFINE VARIABLE a AS JsonArray NO-UNDO.
        DEFINE VARIABLE c AS JsonArray NO-UNDO.
        DEFINE VARIABLE pos AS INTEGER NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE id AS INTEGER NO-UNDO.
        DEFINE VARIABLE chave AS CHARACTER NO-UNDO.
        DEFINE VARIABLE travado AS LOGICAL NO-UNDO.
        travado = wtcc001ln:Travar(lockCadastro).
        IF NOT travado THEN wtcc001ln:Erro("Cadastro em uso. Tente novamente.").
        d = Dados().
        Revisao(d, entrada).
        chave = entrada:GetCharacter("cadastro").
        IF chave <> "baterias" AND chave <> "cenarios" THEN wtcc001ln:Erro("Cadastro inválido.").
        id = entrada:GetInteger("id").
        a = d:GetJsonArray(chave).
        pos = Posicao(a, id).
        IF pos = 0 THEN wtcc001ln:Erro("Registro não encontrado.").
        a:Remove(pos).
        IF chave = "baterias" THEN DO:
            c = d:GetJsonArray("cenarios").
            DO i = c:Length TO 1 BY -1:
                IF c:GetJsonObject(i):GetInteger("bateria_id") = id THEN c:Remove(i).
            END.
        END.
        Salvar(d).
        RETURN d.
        FINALLY:
            IF travado THEN wtcc001ln:Destravar(lockCadastro).
        END FINALLY.
    END METHOD.

    METHOD PUBLIC JsonObject Fonte(INPUT entrada AS JsonObject):
        DEFINE VARIABLE d AS JsonObject NO-UNDO.
        DEFINE VARIABLE a AS JsonArray NO-UNDO.
        DEFINE VARIABLE pos AS INTEGER NO-UNDO.
        DEFINE VARIABLE r AS JsonObject NO-UNDO.
        DEFINE VARIABLE codigo AS LONGCHAR NO-UNDO.
        d = Dados().
        a = d:GetJsonArray("baterias").
        pos = Posicao(a, entrada:GetInteger("bateria_id")).
        IF pos = 0 THEN wtcc001ln:Erro("Bateria não encontrada.").
        IF a:GetJsonObject(pos):GetCharacter("tipo") <> "CENARIOS" THEN wtcc001ln:Erro("Esta bateria usa uma classe ABLUnit já existente.").
        codigo = wtcc001ln:Gerar(a:GetJsonObject(pos), d:GetJsonArray("cenarios"), "wtcc001gerado").
        r = NEW JsonObject().
        r:Add("codigo", codigo).
        RETURN r.
    END METHOD.

    METHOD PUBLIC JsonObject Iniciar(INPUT entrada AS JsonObject):
        DEFINE VARIABLE d AS JsonObject NO-UNDO.
        DEFINE VARIABLE b AS JsonObject NO-UNDO.
        DEFINE VARIABLE c AS JsonObject NO-UNDO.
        DEFINE VARIABLE a AS JsonArray NO-UNDO.
        DEFINE VARIABLE e AS JsonObject NO-UNDO.
        DEFINE VARIABLE core AS JsonObject NO-UNDO.
        DEFINE VARIABLE options AS JsonObject NO-UNDO.
        DEFINE VARIABLE saida AS JsonObject NO-UNDO.
        DEFINE VARIABLE testes AS JsonArray NO-UNDO.
        DEFINE VARIABLE codigo AS LONGCHAR NO-UNDO.
        DEFINE VARIABLE id AS CHARACTER NO-UNDO.
        DEFINE VARIABLE prefixo AS CHARACTER NO-UNDO.
        DEFINE VARIABLE teste AS CHARACTER NO-UNDO.
        DEFINE VARIABLE nomeClasse AS CHARACTER NO-UNDO.
        DEFINE VARIABLE shellScript AS CHARACTER NO-UNDO.
        DEFINE VARIABLE comando AS CHARACTER NO-UNDO.
        DEFINE VARIABLE pos AS INTEGER NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE esperados AS INTEGER NO-UNDO.
        DEFINE VARIABLE timeoutS AS INTEGER NO-UNDO.
        DEFINE VARIABLE travado AS LOGICAL NO-UNDO.
        DEFINE VARIABLE execTravada AS LOGICAL NO-UNDO.
        DEFINE VARIABLE lancado AS LOGICAL NO-UNDO.
        DEFINE VARIABLE anexo AS JsonObject NO-UNDO.
        DEFINE VARIABLE fonteNome AS CHARACTER NO-UNDO.
        DEFINE VARIABLE erroCopia AS INTEGER NO-UNDO.
        IF NOT cfg:GetLogical("execution_enabled") THEN wtcc001ln:Erro("Preencha o .pf de laboratorio e habilite execution_enabled em wtcc001.json.").
        IF entrada:GetInteger("repeticoes") <> 1 THEN wtcc001ln:Erro("Esta versao simples executa uma rodada por solicitacao.").
        timeoutS = cfg:GetInteger("timeout_seconds").
        IF timeoutS < 1 OR timeoutS > 3600 THEN wtcc001ln:Erro("Timeout invalido.").
        IF NOT wtcc001ln:Existe(cfg:GetCharacter("laboratory_pf"))
        OR NOT wtcc001ln:Existe(cfg:GetCharacter("avm"))
        OR NOT wtcc001ln:Existe(base + "/wtcc001runner.p") THEN wtcc001ln:Erro("AVM, runner ou .pf nao localizado.").
        execTravada = wtcc001ln:Travar(lockExecucao).
        IF NOT execTravada THEN wtcc001ln:Erro("Existe uma execucao em andamento. Consulte o historico.").
        IF wtcc001ln:Existe(trabalho + "/results.xml") THEN wtcc001ln:Erro("Ja existe " + trabalho + "/results.xml. Verifique sua origem antes de iniciar outra execucao.").
        travado = wtcc001ln:Travar(lockCadastro).
        IF NOT travado THEN wtcc001ln:Erro("Cadastro em uso.").
        d = Dados().
        Revisao(d, entrada).
        a = d:GetJsonArray("baterias").
        pos = Posicao(a, entrada:GetInteger("bateria_id")).
        IF pos = 0 THEN wtcc001ln:Erro("Bateria nao encontrada.").
        b = a:GetJsonObject(pos).
        id = wtcc001ln:Id().
        prefixo = Pasta(id).
        nomeClasse = "wtcc001_g_" + id.
        IF entrada:Has("anexo_id") AND entrada:GetCharacter("anexo_id") <> "" THEN DO:
            anexo = LocalizarAnexo(entrada:GetCharacter("anexo_id")).
            fonteNome = anexo:GetCharacter("nome").
            IF wtcc001ln:Existe(trabalho + "/" + fonteNome)
            OR wtcc001ln:Existe(trabalho + "/" + ENTRY(1, fonteNome, ".") + ".r") THEN
                wtcc001ln:Erro("Ja existe " + fonteNome + " ou " + ENTRY(1, fonteNome, ".") + ".r em " + trabalho + "; a rodada nao sobrescreve arquivos da pasta.").
            OS-COPY VALUE(trabalho + "/wtcc001_a_" + anexo:GetCharacter("id") + ".src") VALUE(prefixo + "_fonte").
            erroCopia = OS-ERROR.
            IF erroCopia <> 0 OR NOT wtcc001ln:Existe(prefixo + "_fonte") THEN
                wtcc001ln:Erro("Falha ao copiar o fonte anexado " + fonteNome + " (" + STRING(erroCopia) + ").").
        END.
        IF b:GetCharacter("tipo") = "CENARIOS" THEN DO:
            ClassePermitida(b:GetCharacter("classe")).
            codigo = wtcc001ln:Gerar(b, d:GetJsonArray("cenarios"), nomeClasse).
            a = d:GetJsonArray("cenarios").
            DO i = 1 TO a:Length:
                c = a:GetJsonObject(i).
                IF c:GetInteger("bateria_id") = b:GetInteger("id") AND c:GetLogical("ativo") THEN esperados = esperados + 1.
            END.
            wtcc001ln:GravarTexto(trabalho + "/" + nomeClasse + ".cls", codigo).
            teste = nomeClasse + ".cls".
        END.
        ELSE DO:
            teste = Permitido("allowed_test_classes", b:GetCharacter("teste")).
            esperados = b:GetInteger("esperados").
        END.
        wtcc001ln:Gravar(prefixo + "_dados.json", d).
        e = NEW JsonObject().
        e:Add("id", id).
        e:Add("descricao", b:GetCharacter("descricao")).
        e:Add("bateria_id", b:GetInteger("id")).
        e:Add("usuario", usuario).
        e:Add("empresa", vempresa).
        e:Add("unidade", vunidade).
        e:Add("criado_em", STRING(NOW)).
        e:Add("repeticoes", 1).
        e:Add("esperados", esperados).
        e:Add("timeout_s", timeoutS).
        e:Add("status", "NA FILA").
        IF fonteNome <> "" THEN e:Add("anexo", anexo).
        ELSE e:AddNull("anexo").
        wtcc001ln:Gravar(prefixo + "_meta.json", e).
        core = NEW JsonObject().
        options = NEW JsonObject().
        saida = NEW JsonObject().
        saida:Add("location", trabalho).
        saida:Add("format", "xml").
        options:Add("output", saida).
        options:Add("quitOnEnd", FALSE).
        options:Add("writeLog", FALSE).
        options:Add("showErrorMessage", FALSE).
        options:Add("throwError", TRUE).
        core:Add("options", options).
        testes = NEW JsonArray().
        c = NEW JsonObject().
        c:Add("test", teste).
        testes:Add(c).
        core:Add("tests", testes).
        wtcc001ln:Gravar(prefixo + "_cfg.json", core).
        a = d:GetJsonArray("execucoes").
        IF a:Length >= 200 THEN wtcc001ln:Erro("Limite de 200 execucoes no indice.").
        a:Add(e).
        Salvar(d).
        wtcc001ln:GravarTexto(lockExecucao, id).

        /* Comando fixo do servidor, com parametros protegidos por aspas.
           Locks, cadastros e artefatos sao arquivos; nenhum diretorio e criado. */
        shellScript = "cd " + wtcc001ln:Shell(trabalho) + " || exit 73" + CHR(10)
                    + "export DLC=" + wtcc001ln:Shell(cfg:GetCharacter("dlc")) + CHR(10)
                    + "echo PROCFG_HERDADO=" + CHR(34) + "$PROCFG" + CHR(34) + CHR(10)
                    + "export PROCFG=" + wtcc001ln:Shell(IF cfg:Has("procfg") AND cfg:GetCharacter("procfg") <> ""
                                                         THEN cfg:GetCharacter("procfg")
                                                         ELSE cfg:GetCharacter("dlc") + "/progress.cfg") + CHR(10)
                    + "export PROPATH=" + wtcc001ln:Shell(IF fonteNome <> ""
                                                          THEN trabalho + "," + base + "," + cfg:GetCharacter("framework_propath")
                                                          ELSE base + "," + cfg:GetCharacter("framework_propath") + "," + trabalho) + CHR(10)
                    + "export TCC_CADASTROS=" + wtcc001ln:Shell(prefixo + "_dados.json") + CHR(10)
                    + "inicio=$(date +%s)" + CHR(10)
                    + "printf SIM > " + wtcc001ln:Shell(prefixo + "_inicio.txt") + CHR(10)
                    + (IF fonteNome <> ""
                       THEN "if cp " + wtcc001ln:Shell(prefixo + "_fonte") + " " + wtcc001ln:Shell(trabalho + "/" + fonteNome) + "; then" + CHR(10)
                       ELSE "")
                    + "timeout --signal=TERM --kill-after=10 " + wtcc001ln:Shell(STRING(timeoutS) + "s")
                    + " " + wtcc001ln:Shell(cfg:GetCharacter("avm"))
                    + " -b -pf " + wtcc001ln:Shell(cfg:GetCharacter("laboratory_pf"))
                    + " -T " + wtcc001ln:Shell(trabalho)
                    + " -cpinternal ISO8859-1 -cpstream ISO8859-1 -p " + wtcc001ln:Shell(base + "/wtcc001runner.p")
                    + " -param " + wtcc001ln:Shell("CFG=" + prefixo + "_cfg.json")
                    + " > " + wtcc001ln:Shell(prefixo + "_avm.log") + " 2>&1" + CHR(10)
                    + "retorno=$?" + CHR(10)
                    + (IF fonteNome <> ""
                       THEN "rm -f " + wtcc001ln:Shell(trabalho + "/" + fonteNome) + CHR(10)
                          + "else" + CHR(10)
                          + "echo FALHA_COPIA_FONTE" + CHR(10)
                          + "retorno=74" + CHR(10)
                          + "fi" + CHR(10)
                       ELSE "")
                    + "fim=$(date +%s)" + CHR(10)
                    + "printf '%s' " + CHR(34) + "$((fim-inicio))" + CHR(34) + " > " + wtcc001ln:Shell(prefixo + "_duracao.txt") + CHR(10)
                    + "printf '%s' " + CHR(34) + "$retorno" + CHR(34) + " > " + wtcc001ln:Shell(prefixo + "_exit.tmp") + CHR(10)
                    + "mv " + wtcc001ln:Shell(prefixo + "_exit.tmp") + " " + wtcc001ln:Shell(prefixo + "_exit.txt") + CHR(10)
                    + "if [ " + CHR(34) + "$(cat " + wtcc001ln:Shell(lockExecucao) + " 2>/dev/null)" + CHR(34)
                    + " = " + wtcc001ln:Shell(id) + " ]; then rm -f " + wtcc001ln:Shell(lockExecucao) + "; fi".
        comando = "nohup /bin/sh -c " + wtcc001ln:Shell(shellScript)
                + " > " + wtcc001ln:Shell(prefixo + "_launcher.log") + " 2>&1 < /dev/null &".
        OS-COMMAND SILENT VALUE(comando).
        lancado = TRUE.
        RETURN e.
        FINALLY:
            IF travado THEN wtcc001ln:Destravar(lockCadastro).
            IF execTravada AND NOT lancado THEN wtcc001ln:Destravar(lockExecucao).
        END FINALLY.
    END METHOD.

    METHOD PRIVATE JsonObject Anexos():
        DEFINE VARIABLE d AS JsonObject NO-UNDO.
        IF wtcc001ln:Existe(anexosArq) THEN RETURN wtcc001ln:Ler(anexosArq).
        d = NEW JsonObject().
        d:Add("anexos", NEW JsonArray()).
        RETURN d.
    END METHOD.

    METHOD PRIVATE STATIC CHARACTER NomeFonte(INPUT nome AS CHARACTER):
        DEFINE VARIABLE raiz AS CHARACTER NO-UNDO.
        IF nome = ? OR LENGTH(nome) > 80 OR NUM-ENTRIES(nome, ".") <> 2 THEN
            wtcc001ln:Erro("Nome de fonte invalido: use <nome>.cls ou <nome>.p.").
        raiz = ENTRY(1, nome, ".").
        IF raiz = "" OR LOOKUP(ENTRY(2, nome, "."), "cls,p") = 0
        OR NOT wtcc001ln:CaracteresValidos(raiz, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-") THEN
            wtcc001ln:Erro("Nome de fonte invalido: use <nome>.cls ou <nome>.p, com letras, numeros, _ e -: " + nome).
        IF raiz BEGINS "wtcc001" THEN wtcc001ln:Erro("Fontes do laboratorio nao podem ser anexados: " + nome).
        RETURN nome.
    END METHOD.

    METHOD PRIVATE STATIC VOID AcrescentarTexto(INPUT p AS CHARACTER, INPUT t AS LONGCHAR):
        COPY-LOB FROM t TO FILE p APPEND CONVERT TARGET CODEPAGE "ISO8859-1".
    END METHOD.

    METHOD PRIVATE STATIC VOID ValidarIdAnexo(INPUT id AS CHARACTER):
        IF id = ? OR LENGTH(id) <> 32 OR NOT wtcc001ln:CaracteresValidos(id, "0123456789abcdef") THEN
            wtcc001ln:Erro("Identificador de anexo invalido.").
    END METHOD.

    METHOD PRIVATE JsonObject LocalizarAnexo(INPUT id AS CHARACTER):
        DEFINE VARIABLE lista AS JsonArray NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        wtcc001ln:ValidarIdAnexo(id).
        lista = Anexos():GetJsonArray("anexos").
        DO i = 1 TO lista:Length:
            IF lista:GetJsonObject(i):GetCharacter("id") = id THEN RETURN lista:GetJsonObject(i).
        END.
        wtcc001ln:Erro("Fonte anexado nao encontrado: " + id + ". Atualize a tela.").
        RETURN ?.
    END METHOD.

    METHOD PUBLIC JsonObject AnexoParte(INPUT entrada AS JsonObject):
        DEFINE VARIABLE upload AS CHARACTER NO-UNDO.
        DEFINE VARIABLE estado AS JsonObject NO-UNDO.
        DEFINE VARIABLE d AS JsonObject NO-UNDO.
        DEFINE VARIABLE lista AS JsonArray NO-UNDO.
        DEFINE VARIABLE anexo AS JsonObject NO-UNDO.
        DEFINE VARIABLE r AS JsonObject NO-UNDO.
        DEFINE VARIABLE parte AS INTEGER NO-UNDO.
        DEFINE VARIABLE tamanho AS INT64 NO-UNDO.
        DEFINE VARIABLE recebido AS INT64 NO-UNDO.
        DEFINE VARIABLE erroArquivo AS INTEGER NO-UNDO.
        DEFINE VARIABLE arquivoEstado AS CHARACTER NO-UNDO.
        DEFINE VARIABLE arquivoParcial AS CHARACTER NO-UNDO.
        DEFINE VARIABLE conteudo AS MEMPTR NO-UNDO.
        DEFINE VARIABLE travado AS LOGICAL NO-UNDO.
        DEFINE VARIABLE metodos AS JsonArray NO-UNDO.
        DEFINE VARIABLE lidos AS JsonArray NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        parte = entrada:GetInteger("parte").
        IF parte = 1 THEN DO:
            upload = wtcc001ln:Id().
            tamanho = entrada:GetInt64("tamanho").
            IF tamanho = ? OR tamanho <= 0 OR tamanho > 2000000 THEN wtcc001ln:Erro("Fonte vazio ou maior que 2.000.000 bytes.").
            estado = NEW JsonObject().
            estado:Add("nome", wtcc001ln:NomeFonte(entrada:GetCharacter("nome"))).
            estado:Add("tamanho", tamanho).
            estado:Add("empresa", vempresa).
            estado:Add("unidade", vunidade).
            estado:Add("usuario", usuario).
            estado:Add("partes", 0).
        END.
        ELSE DO:
            upload = entrada:GetCharacter("upload").
            wtcc001ln:ValidarIdAnexo(upload).
            IF NOT wtcc001ln:Existe(trabalho + "/wtcc001_u_" + upload + ".json") THEN wtcc001ln:Erro("Envio nao encontrado: " + upload + ".").
            estado = wtcc001ln:Ler(trabalho + "/wtcc001_u_" + upload + ".json").
            IF estado:GetInteger("empresa") <> vempresa OR estado:GetInteger("unidade") <> vunidade
            OR estado:GetCharacter("usuario") <> usuario THEN wtcc001ln:Erro("Envio pertence a outro usuario.").
            tamanho = estado:GetInt64("tamanho").
        END.
        ASSIGN arquivoEstado = trabalho + "/wtcc001_u_" + upload + ".json"
               arquivoParcial = trabalho + "/wtcc001_u_" + upload + ".tmp".
        IF parte <> estado:GetInteger("partes") + 1 THEN
            wtcc001ln:Erro("Parte " + STRING(parte) + " fora de ordem; esperada " + STRING(estado:GetInteger("partes") + 1) + ".").
        wtcc001ln:AcrescentarTexto(arquivoParcial, entrada:GetLongchar("conteudo")).
        FILE-INFO:FILE-NAME = arquivoParcial.
        recebido = FILE-INFO:FILE-SIZE.
        IF recebido = ? OR recebido > tamanho THEN wtcc001ln:Erro("Envio excedeu o tamanho declarado do arquivo.").
        estado:Set("partes", parte).
        wtcc001ln:Gravar(arquivoEstado, estado).
        r = NEW JsonObject().
        r:Add("upload", upload).
        IF NOT entrada:GetLogical("fim") THEN RETURN r.
        IF recebido <> tamanho THEN
            wtcc001ln:Erro("Tamanho recebido (" + STRING(recebido) + " bytes) difere do arquivo (" + STRING(tamanho) + " bytes).").
        COPY-LOB FROM FILE arquivoParcial TO conteudo.
        anexo = NEW JsonObject().
        anexo:Add("id", upload).
        anexo:Add("nome", estado:GetCharacter("nome")).
        anexo:Add("tamanho", tamanho).
        anexo:Add("sha256", LC(HEX-ENCODE(MESSAGE-DIGEST("SHA-256", conteudo)))).
        anexo:Add("classe", IF ENTRY(2, estado:GetCharacter("nome"), ".") = "cls" THEN ENTRY(1, estado:GetCharacter("nome"), ".") ELSE "").
        metodos = NEW JsonArray().
        IF anexo:GetCharacter("classe") <> "" AND entrada:Has("metodos") THEN DO:
            lidos = entrada:GetJsonArray("metodos").
            DO i = 1 TO MINIMUM(lidos:Length, 150):
                IF wtcc001ln:MetodoValido(lidos:GetJsonObject(i)) THEN metodos:Add(lidos:GetJsonObject(i)).
            END.
        END.
        anexo:Add("metodos", metodos).
        anexo:Add("criado_em", STRING(NOW)).
        anexo:Add("usuario", usuario).
        travado = wtcc001ln:Travar(lockAnexos).
        IF NOT travado THEN wtcc001ln:Erro("Lista de fontes anexados em uso. Tente novamente.").
        d = Anexos().
        lista = d:GetJsonArray("anexos").
        IF lista:Length >= 50 THEN wtcc001ln:Erro("Limite de 50 fontes anexados. Exclua um anexo antigo.").
        OS-RENAME VALUE(arquivoParcial) VALUE(trabalho + "/wtcc001_a_" + upload + ".src").
        erroArquivo = OS-ERROR.
        IF erroArquivo <> 0 THEN wtcc001ln:Erro("Falha ao registrar o fonte anexado (" + STRING(erroArquivo) + ").").
        lista:Add(anexo).
        wtcc001ln:Gravar(anexosArq, d).
        OS-DELETE VALUE(arquivoEstado).
        r:Add("anexo", anexo).
        r:Add("anexos", lista).
        RETURN r.
        FINALLY:
            SET-SIZE(conteudo) = 0.
            IF travado THEN wtcc001ln:Destravar(lockAnexos).
        END FINALLY.
    END METHOD.

    METHOD PUBLIC JsonObject ExcluirAnexo(INPUT entrada AS JsonObject):
        DEFINE VARIABLE d AS JsonObject NO-UNDO.
        DEFINE VARIABLE lista AS JsonArray NO-UNDO.
        DEFINE VARIABLE r AS JsonObject NO-UNDO.
        DEFINE VARIABLE id AS CHARACTER NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE pos AS INTEGER NO-UNDO.
        DEFINE VARIABLE travado AS LOGICAL NO-UNDO.
        id = entrada:GetCharacter("id").
        wtcc001ln:ValidarIdAnexo(id).
        travado = wtcc001ln:Travar(lockAnexos).
        IF NOT travado THEN wtcc001ln:Erro("Lista de fontes anexados em uso. Tente novamente.").
        d = Anexos().
        lista = d:GetJsonArray("anexos").
        DO i = 1 TO lista:Length:
            IF lista:GetJsonObject(i):GetCharacter("id") = id THEN pos = i.
        END.
        IF pos = 0 THEN wtcc001ln:Erro("Fonte anexado nao encontrado: " + id + ".").
        lista:Remove(pos).
        wtcc001ln:Gravar(anexosArq, d).
        IF wtcc001ln:Existe(trabalho + "/wtcc001_a_" + id + ".src") THEN OS-DELETE VALUE(trabalho + "/wtcc001_a_" + id + ".src").
        r = NEW JsonObject().
        r:Add("anexos", lista).
        RETURN r.
        FINALLY:
            IF travado THEN wtcc001ln:Destravar(lockAnexos).
        END FINALLY.
    END METHOD.

    METHOD PRIVATE CHARACTER Pasta(INPUT id AS CHARACTER):
        IF LENGTH(id) <> 32 OR NOT wtcc001ln:CaracteresValidos(id, "0123456789abcdef") THEN wtcc001ln:Erro("Execucao invalida.").
        RETURN trabalho + "/wtcc001_e_" + id.
    END METHOD.

    METHOD PUBLIC JsonObject Resultado(INPUT id AS CHARACTER):
        DEFINE VARIABLE prefixo AS CHARACTER NO-UNDO.
        DEFINE VARIABLE r AS JsonObject NO-UNDO.
        DEFINE VARIABLE m AS JsonObject NO-UNDO.
        DEFINE VARIABLE medidas AS JsonArray NO-UNDO.
        DEFINE VARIABLE problemasExec AS JsonArray NO-UNDO.
        DEFINE VARIABLE estado AS CHARACTER NO-UNDO.
        DEFINE VARIABLE retorno AS CHARACTER NO-UNDO.
        DEFINE VARIABLE completo AS INTEGER NO-UNDO.
        DEFINE VARIABLE criado AS DATETIME-TZ NO-UNDO.
        prefixo = Pasta(id).
        r = wtcc001ln:Ler(prefixo + "_meta.json").
        IF r:GetInteger("empresa") <> vempresa OR r:GetInteger("unidade") <> vunidade THEN wtcc001ln:Erro("Execucao pertence a outra empresa/unidade.").
        medidas = NEW JsonArray().
        problemasExec = NEW JsonArray().
        estado = IF wtcc001ln:Existe(prefixo + "_inicio.txt") THEN "EXECUTANDO" ELSE "NA FILA".
        IF wtcc001ln:Existe(prefixo + "_exit.txt") THEN DO:
            completo = 1.
            retorno = TRIM(wtcc001ln:Texto(prefixo + "_exit.txt")).
            IF wtcc001ln:Existe(prefixo + "_resultado.json") THEN m = wtcc001ln:Ler(prefixo + "_resultado.json").
            ELSE DO:
                m = NEW JsonObject().
                m:Add("status", "ERRO").
                m:Add("mensagem", "AVM nao produziu resultado. Consulte os logs.").
            END.
            m:Add("repeticao", 1).
            m:Add("exit_code", retorno).
            m:AddNull("duracao_parede_s").
            IF wtcc001ln:Existe(prefixo + "_duracao.txt") THEN
                m:Set("duracao_parede_s", DECIMAL(TRIM(wtcc001ln:Texto(prefixo + "_duracao.txt")))).
            IF retorno <> "0" THEN DO:
                m:Set("status", "ERRO").
                problemasExec:Add("AVM/timeout retornou " + retorno + ".").
            END.
            estado = m:GetCharacter("status").
            IF estado = "ERRO" THEN estado = "INCONCLUSIVO".
            medidas:Add(m).
        END.
        ELSE DO:
            criado = DATETIME-TZ(r:GetCharacter("criado_em")) NO-ERROR.
            IF NOT ERROR-STATUS:ERROR AND criado <> ? THEN DO:
                IF estado = "NA FILA" AND NOW - criado > 60000 THEN DO:
                    estado = "INCONCLUSIVO".
                    problemasExec:Add("O processo nao confirmou inicio. Confira OS-COMMAND e launcher.log.").
                END.
                ELSE IF NOW - criado > (r:GetInteger("timeout_s") + 70) * 1000 THEN DO:
                    estado = "INCONCLUSIVO".
                    problemasExec:Add("Execucao excedeu o prazo. Confira os processos antes de remover o arquivo de lock.").
                END.
            END.
        END.
        r:Set("status", estado).
        r:Add("concluidas", completo).
        r:Add("repeticoes_aprovadas", IF estado = "APROVADO" THEN 1 ELSE 0).
        r:Add("medidas", medidas).
        r:Add("problemas", problemasExec).
        r:AddNull("media_tempo_testes_s").
        IF completo = 1 THEN DO:
            IF m:Has("tempo_testes_s") THEN DO:
                IF NOT m:IsNull("tempo_testes_s") THEN
                    r:Set("media_tempo_testes_s", m:GetDecimal("tempo_testes_s")).
            END.
        END.
        RETURN r.
    END METHOD.

    METHOD PUBLIC JsonObject Logs(INPUT entrada AS JsonObject):
        DEFINE VARIABLE prefixo AS CHARACTER NO-UNDO.
        DEFINE VARIABLE r AS JsonObject NO-UNDO.
        DEFINE VARIABLE meta AS JsonObject NO-UNDO.
        prefixo = Pasta(entrada:GetCharacter("id")).
        IF NOT wtcc001ln:Existe(prefixo + "_meta.json") THEN wtcc001ln:Erro("Execucao nao encontrada.").
        meta = wtcc001ln:Ler(prefixo + "_meta.json").
        IF meta:GetInteger("empresa") <> vempresa OR meta:GetInteger("unidade") <> vunidade THEN wtcc001ln:Erro("Execucao pertence a outra empresa/unidade.").
        r = NEW JsonObject().
        r:Add("avm", IF wtcc001ln:Existe(prefixo + "_avm.log") THEN wtcc001ln:Texto(prefixo + "_avm.log") ELSE "").
        r:Add("launcher", IF wtcc001ln:Existe(prefixo + "_launcher.log") THEN wtcc001ln:Texto(prefixo + "_launcher.log") ELSE "").
        r:Add("ablunit", IF wtcc001ln:Existe(prefixo + "_ablunit.log") THEN wtcc001ln:Texto(prefixo + "_ablunit.log") ELSE "").
        RETURN r.
    END METHOD.

/* Geracao ABLUnit. */

    METHOD PRIVATE STATIC VOID ValidarTexto(INPUT t AS CHARACTER):
        IF t = ? OR LENGTH(t) > 8000 OR INDEX(t, CHR(0)) > 0 THEN
            wtcc001ln:Erro("Texto inválido: limite de 8.000 caracteres por campo.").
    END METHOD.

    METHOD PRIVATE STATIC CHARACTER TiposAceitos():
        RETURN "CHARACTER,LONGCHAR,INTEGER,INT64,DECIMAL,DATE,LOGICAL".
    END METHOD.

    METHOD PRIVATE STATIC LOGICAL MetodoValido(INPUT m AS JsonObject):
        DEFINE VARIABLE tipos AS JsonArray NO-UNDO.
        DEFINE VARIABLE nomes AS JsonArray NO-UNDO.
        DEFINE VARIABLE identificador AS CHARACTER NO-UNDO INITIAL "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        IF m:GetCharacter("nome") = "" OR LENGTH(m:GetCharacter("nome")) > 100
        OR NOT wtcc001ln:CaracteresValidos(m:GetCharacter("nome"), identificador) THEN RETURN FALSE.
        IF LOOKUP(m:GetCharacter("retorno"), wtcc001ln:TiposAceitos()) = 0 THEN RETURN FALSE.
        IF m:GetLogical("estatico") = ? THEN RETURN FALSE.
        ASSIGN tipos = m:GetJsonArray("tipos")
               nomes = m:GetJsonArray("nomes").
        IF tipos:Length > 30 OR nomes:Length <> tipos:Length THEN RETURN FALSE.
        DO i = 1 TO tipos:Length:
            IF LOOKUP(tipos:GetCharacter(i), wtcc001ln:TiposAceitos()) = 0 THEN RETURN FALSE.
            IF LENGTH(nomes:GetCharacter(i)) > 100 OR NOT wtcc001ln:CaracteresValidos(nomes:GetCharacter(i), identificador) THEN RETURN FALSE.
        END.
        RETURN TRUE.
        CATCH erroMetodo AS Progress.Lang.Error:
            RETURN FALSE.
        END CATCH.
    END METHOD.

    METHOD PUBLIC STATIC VOID Validar(INPUT c AS JsonObject):
        DEFINE VARIABLE e AS JsonObject NO-UNDO.
        DEFINE VARIABLE m AS JsonObject NO-UNDO.
        DEFINE VARIABLE a AS JsonArray NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE total AS INTEGER NO-UNDO.
        e = c:GetJsonObject("entradas").
        ValidarTexto(e:GetCharacter("esperado")).
        CASE c:GetCharacter("modelo"):
            WHEN "addWhere" THEN DO:
                ValidarTexto(e:GetCharacter("where")).
                ValidarTexto(e:GetCharacter("condicao")).
            END.
            WHEN "setErro" THEN DO:
                a = e:GetJsonArray("mensagens").
                IF a:Length > 50 THEN wtcc001ln:Erro("Máximo de 50 mensagens.").
                DO i = 1 TO a:Length:
                    ValidarTexto(a:GetCharacter(i)).
                    total = total + LENGTH(a:GetCharacter(i)).
                END.
                IF total > 16000 THEN wtcc001ln:Erro("Mensagens excedem 16.000 caracteres.").
            END.
            WHEN "metodo" THEN DO:
                m = NEW JsonObject().
                m:Add("nome", e:GetCharacter("metodo")).
                m:Add("estatico", e:GetLogical("estatico")).
                m:Add("retorno", e:GetCharacter("retorno")).
                m:Add("tipos", e:GetJsonArray("tipos")).
                m:Add("nomes", e:GetJsonArray("nomes")).
                IF NOT wtcc001ln:MetodoValido(m) THEN wtcc001ln:Erro("Metodo, tipos ou retorno invalidos no cenario.").
                a = e:GetJsonArray("argumentos").
                IF a:Length <> e:GetJsonArray("tipos"):Length THEN wtcc001ln:Erro("Quantidade de argumentos difere da assinatura do metodo.").
                DO i = 1 TO a:Length:
                    ValidarTexto(a:GetCharacter(i)).
                END.
            END.
            OTHERWISE wtcc001ln:Erro("Modelo desconhecido.").
        END CASE.
    END METHOD.

    METHOD PRIVATE STATIC CHARACTER Conversao(INPUT tipo AS CHARACTER, INPUT expressao AS CHARACTER):
        DEFINE VARIABLE convertido AS CHARACTER NO-UNDO.
        CASE CAPS(tipo):
            WHEN "CHARACTER" OR WHEN "LONGCHAR" THEN convertido = expressao.
            WHEN "INTEGER" THEN convertido = 'INTEGER(' + expressao + ')'.
            WHEN "INT64" THEN convertido = 'INT64(' + expressao + ')'.
            WHEN "DECIMAL" THEN convertido = 'DECIMAL(REPLACE(REPLACE(' + expressao + ', ",", "."), ".", SESSION:NUMERIC-DECIMAL-POINT))'.
            WHEN "DATE" THEN convertido = 'DATE(INTEGER(ENTRY(2, ' + expressao + ', "/")), INTEGER(ENTRY(1, ' + expressao + ', "/")), INTEGER(ENTRY(3, ' + expressao + ', "/")))'.
            WHEN "LOGICAL" THEN convertido = '(LOOKUP(' + expressao + ', "yes,true,sim,s,1") > 0)'.
            OTHERWISE wtcc001ln:Erro("Tipo nao suportado: " + tipo).
        END CASE.
        RETURN '(IF ' + expressao + ' = "?" THEN ? ELSE ' + convertido + ')'.
    END METHOD.

    METHOD PRIVATE STATIC CHARACTER Comparacao(INPUT retorno AS CHARACTER, INPUT chamada AS CHARACTER):
        CASE CAPS(retorno):
            WHEN "CHARACTER" OR WHEN "LONGCHAR" THEN RETURN 'Igual(entradas:GetCharacter("esperado"), STRING(' + chamada + ')).'.
            WHEN "INTEGER" OR WHEN "INT64" OR WHEN "DECIMAL" THEN RETURN 'IgualNumero(entradas:GetCharacter("esperado"), ' + chamada + ').'.
            WHEN "DATE" THEN RETURN 'IgualData(entradas:GetCharacter("esperado"), ' + chamada + ').'.
            WHEN "LOGICAL" THEN RETURN 'IgualLogico(entradas:GetCharacter("esperado"), ' + chamada + ').'.
        END CASE.
        wtcc001ln:Erro("Retorno nao suportado: " + retorno).
        RETURN "".
    END METHOD.

    METHOD PRIVATE STATIC CHARACTER Corpo(INPUT c AS JsonObject, INPUT classe AS CHARACTER):
        DEFINE VARIABLE e AS JsonObject NO-UNDO.
        DEFINE VARIABLE tipos AS JsonArray NO-UNDO.
        DEFINE VARIABLE chamada AS CHARACTER NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        CASE c:GetCharacter("modelo"):
            WHEN "metodo" THEN DO:
                e = c:GetJsonObject("entradas").
                tipos = e:GetJsonArray("tipos").
                chamada = (IF e:GetLogical("estatico") THEN classe ELSE "oregra") + ":" + e:GetCharacter("metodo") + "(".
                DO i = 1 TO tipos:Length:
                    chamada = chamada + (IF i > 1 THEN ", " ELSE "")
                            + wtcc001ln:Conversao(tipos:GetCharacter(i), 'argumentos:GetCharacter(' + STRING(i) + ')').
                END.
                chamada = chamada + ")".
                RETURN 'argumentos = entradas:GetJsonArray("argumentos").' + CHR(10)
                     + '    ' + wtcc001ln:Comparacao(e:GetCharacter("retorno"), chamada).
            END.
            WHEN "addWhere" THEN RETURN
                'Igual(entradas:GetCharacter("esperado"), oregra:addWhere(entradas:GetCharacter("where"), entradas:GetCharacter("condicao"))).'.
            WHEN "setErro" THEN RETURN
                'mensagens = entradas:GetJsonArray("mensagens").' + CHR(10)
              + '    DO i = 1 TO mensagens:Length:' + CHR(10)
              + '      oregra:setErro(mensagens:GetCharacter(i)).' + CHR(10)
              + '    END.' + CHR(10)
              + '    Igual(entradas:GetCharacter("esperado"), oregra:msgErros()).'.
        END CASE.
        wtcc001ln:Erro("Modelo desconhecido.").
        RETURN "".
    END METHOD.

    METHOD PUBLIC STATIC LONGCHAR Gerar(INPUT b AS JsonObject, INPUT cenarios AS JsonArray, INPUT nomeClasse AS CHARACTER):
        DEFINE VARIABLE codigo AS LONGCHAR NO-UNDO.
        DEFINE VARIABLE c AS JsonObject NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE qtd AS INTEGER NO-UNDO.
        DEFINE VARIABLE classe AS CHARACTER NO-UNDO.
        classe = b:GetCharacter("classe").
        IF classe = "" OR NOT wtcc001ln:CaracteresValidos(classe, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.") THEN
            wtcc001ln:Erro("Nome de classe inválido.").
        codigo = '/* Gerado pelo cadastro. Entradas: variável TCC_CADASTROS. */' + CHR(10)
               + 'ROUTINE-LEVEL ON ERROR UNDO, THROW.' + CHR(10)
               + 'USING OpenEdge.Core.Assert.' + CHR(10)
               + 'USING Progress.Json.ObjectModel.*.' + CHR(10)
               + 'CLASS ' + nomeClasse + ':' + CHR(10)
               + '  DEFINE PRIVATE VARIABLE snapshot AS JsonObject NO-UNDO.' + CHR(10)
               + '  METHOD PRIVATE VOID Igual(INPUT a AS CHARACTER, INPUT b AS CHARACTER):' + CHR(10)
               + '    DEFINE VARIABLE ok AS LOGICAL NO-UNDO.' + CHR(10)
               + '    ok = FALSE.' + CHR(10)
               + '    IF a <> ? AND b <> ? THEN ok = LENGTH(a) = LENGTH(b) AND COMPARE(a, "EQ", b, "RAW").' + CHR(10)
               + '    IF a = "?" AND b = ? THEN ok = TRUE.' + CHR(10)
               + '    Assert:IsTrue(ok, "Esperado: [" + (IF a = ? THEN "?" ELSE a) + "] / Obtido: [" + (IF b = ? THEN "?" ELSE b) + "].").' + CHR(10)
               + '  END METHOD.' + CHR(10)
               + '  METHOD PRIVATE VOID IgualNumero(INPUT a AS CHARACTER, INPUT b AS DECIMAL):' + CHR(10)
               + '    DEFINE VARIABLE esperado AS DECIMAL NO-UNDO.' + CHR(10)
               + '    esperado = (IF a = "?" THEN ? ELSE DECIMAL(REPLACE(REPLACE(a, ",", "."), ".", SESSION:NUMERIC-DECIMAL-POINT))).' + CHR(10)
               + '    Assert:IsTrue((esperado = b) = TRUE, "Esperado: [" + a + "] / Obtido: [" + (IF b = ? THEN "?" ELSE STRING(b)) + "].").' + CHR(10)
               + '  END METHOD.' + CHR(10)
               + '  METHOD PRIVATE VOID IgualData(INPUT a AS CHARACTER, INPUT b AS DATE):' + CHR(10)
               + '    Igual(a, IF b = ? THEN "?" ELSE STRING(b, "99/99/9999")).' + CHR(10)
               + '  END METHOD.' + CHR(10)
               + '  METHOD PRIVATE VOID IgualLogico(INPUT a AS CHARACTER, INPUT b AS LOGICAL):' + CHR(10)
               + '    DEFINE VARIABLE esperado AS LOGICAL NO-UNDO.' + CHR(10)
               + '    esperado = (IF a = "?" THEN ? ELSE LOOKUP(a, "yes,true,sim,s,1") > 0).' + CHR(10)
               + '    Assert:IsTrue((esperado = b) = TRUE, "Esperado: [" + a + "] / Obtido: [" + (IF b = ? THEN "?" ELSE TRIM(STRING(b, "yes/no"))) + "].").' + CHR(10)
               + '  END METHOD.' + CHR(10)
               + '  @Before.' + CHR(10)
               + '  METHOD PUBLIC VOID Carregar():' + CHR(10)
               + '    DEFINE VARIABLE parser AS ObjectModelParser NO-UNDO.' + CHR(10)
               + '    parser = NEW ObjectModelParser().' + CHR(10)
               + '    snapshot = CAST(parser:ParseFile(OS-GETENV("TCC_CADASTROS")), JsonObject).' + CHR(10)
               + '    FINALLY:' + CHR(10)
               + '      IF VALID-OBJECT(parser) THEN DELETE OBJECT parser.' + CHR(10)
               + '    END FINALLY.' + CHR(10)
               + '  END METHOD.' + CHR(10)
               + '  @After.' + CHR(10)
               + '  METHOD PUBLIC VOID Liberar():' + CHR(10)
               + '    IF VALID-OBJECT(snapshot) THEN DELETE OBJECT snapshot.' + CHR(10)
               + '  END METHOD.' + CHR(10)
               + '  METHOD PRIVATE JsonObject Entrada(INPUT id AS INTEGER):' + CHR(10)
               + '    DEFINE VARIABLE a AS JsonArray NO-UNDO.' + CHR(10)
               + '    DEFINE VARIABLE i AS INTEGER NO-UNDO.' + CHR(10)
               + '    a = snapshot:GetJsonArray("cenarios").' + CHR(10)
               + '    DO i = 1 TO a:Length:' + CHR(10)
               + '      IF a:GetJsonObject(i):GetInteger("id") = id THEN RETURN a:GetJsonObject(i):GetJsonObject("entradas").' + CHR(10)
               + '    END.' + CHR(10)
               + '    UNDO, THROW NEW Progress.Lang.AppError("Cenário ausente no snapshot.", 9001).' + CHR(10)
               + '  END METHOD.' + CHR(10).
        DO i = 1 TO cenarios:Length:
            c = cenarios:GetJsonObject(i).
            IF c:GetInteger("bateria_id") <> b:GetInteger("id") OR NOT c:GetLogical("ativo") THEN NEXT.
            Validar(c).
            qtd = qtd + 1.
            codigo = codigo + '  @Test.' + CHR(10)
                   + '  METHOD PUBLIC VOID Caso_' + STRING(c:GetInteger("id")) + '():' + CHR(10)
                   + '    DEFINE VARIABLE oregra AS ' + classe + ' NO-UNDO.' + CHR(10)
                   + '    DEFINE VARIABLE entradas AS JsonObject NO-UNDO.' + CHR(10)
                   + '    DEFINE VARIABLE mensagens AS JsonArray NO-UNDO.' + CHR(10)
                   + '    DEFINE VARIABLE argumentos AS JsonArray NO-UNDO.' + CHR(10)
                   + '    DEFINE VARIABLE i AS INTEGER NO-UNDO.' + CHR(10)
                   + '    entradas = Entrada(' + STRING(c:GetInteger("id")) + ').' + CHR(10)
                   + (IF c:GetCharacter("modelo") = "metodo" AND c:GetJsonObject("entradas"):GetLogical("estatico")
                      THEN ''
                      ELSE '    oregra = NEW ' + classe + '().' + CHR(10))
                   + '    ' + Corpo(c, classe) + CHR(10)
                   + '    FINALLY:' + CHR(10)
                   + '      IF VALID-OBJECT(oregra) THEN DELETE OBJECT oregra.' + CHR(10)
                   + '    END FINALLY.' + CHR(10)
                   + '  END METHOD.' + CHR(10).
        END.
        IF qtd = 0 THEN wtcc001ln:Erro("Cadastre ao menos um cenário ativo.").
        RETURN codigo + 'END CLASS.' + CHR(10).
    END METHOD.

/* Leitura do XML. */

    METHOD PRIVATE CHARACTER Nome(INPUT n AS HANDLE):
        RETURN ENTRY(NUM-ENTRIES(n:NAME, ":"), n:NAME, ":").
    END METHOD.

    METHOD PRIVATE CHARACTER Conteudo(INPUT n AS HANDLE, INPUT profundidade AS INTEGER):
        DEFINE VARIABLE filho AS HANDLE NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE t AS CHARACTER NO-UNDO.
        IF profundidade > 100 THEN RETURN "[mensagem excedeu limite]".
        IF n:SUBTYPE = "TEXT" OR n:SUBTYPE = "CDATA-SECTION" THEN RETURN n:NODE-VALUE.
        CREATE X-NODEREF filho.
        DO i = 1 TO n:NUM-CHILDREN:
            n:GET-CHILD(filho, i).
            t = SUBSTRING(t + Conteudo(filho, profundidade + 1), 1, 12000).
        END.
        RETURN t.
        FINALLY:
            IF VALID-HANDLE(filho) THEN DELETE OBJECT filho.
        END FINALLY.
    END METHOD.

    METHOD PRIVATE VOID Caso(INPUT n AS HANDLE, INPUT suite AS CHARACTER):
        DEFINE VARIABLE obj AS JsonObject NO-UNDO.
        DEFINE VARIABLE filho AS HANDLE NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE nomeCaso AS CHARACTER NO-UNDO.
        DEFINE VARIABLE classe AS CHARACTER NO-UNDO.
        DEFINE VARIABLE chave AS CHARACTER CASE-SENSITIVE NO-UNDO.
        DEFINE VARIABLE estado AS CHARACTER NO-UNDO INITIAL "APROVADO".
        DEFINE VARIABLE msg AS CHARACTER NO-UNDO.
        DEFINE VARIABLE tipo AS CHARACTER NO-UNDO.
        DEFINE VARIABLE tempoTexto AS CHARACTER NO-UNDO.
        DEFINE VARIABLE tempo AS DECIMAL NO-UNDO.
        obj = NEW JsonObject().
        ASSIGN nomeCaso = n:GET-ATTRIBUTE("name")
               classe = n:GET-ATTRIBUTE("classname").
        IF classe = "" THEN classe = suite.
        IF nomeCaso = "" THEN problemas:Add("Testcase sem nome.").
        chave = STRING(LENGTH(classe)) + ":" + classe + STRING(LENGTH(nomeCaso)) + ":" + nomeCaso.
        FIND ttIdentidade WHERE ttIdentidade.chave = chave NO-ERROR.
        IF AVAILABLE ttIdentidade THEN problemas:Add("Testcase duplicado: " + classe + "." + nomeCaso).
        ELSE DO:
            CREATE ttIdentidade.
            ttIdentidade.chave = chave.
        END.
        CREATE X-NODEREF filho.
        DO i = 1 TO n:NUM-CHILDREN:
            n:GET-CHILD(filho, i).
            CASE Nome(filho):
                WHEN "failure" THEN DO:
                    tipo = filho:GET-ATTRIBUTE("type").
                    IF tipo <> "" AND INDEX(tipo, "Assertion") = 0 THEN estado = "ERRO".
                    ELSE IF estado <> "ERRO" THEN estado = "FALHA".
                    msg = SUBSTRING(msg + filho:GET-ATTRIBUTE("message") + " " + Conteudo(filho, 0), 1, 12000).
                END.
                WHEN "error" THEN DO:
                    estado = "ERRO".
                    msg = SUBSTRING(msg + filho:GET-ATTRIBUTE("message") + " " + Conteudo(filho, 0), 1, 12000).
                END.
                WHEN "skipped" THEN DO:
                    IF estado = "APROVADO" THEN estado = "IGNORADO".
                    msg = SUBSTRING(msg + filho:GET-ATTRIBUTE("message") + " " + Conteudo(filho, 0), 1, 12000).
                END.
            END CASE.
        END.
        CASE estado:
            WHEN "APROVADO" THEN aprovados = aprovados + 1.
            WHEN "FALHA" THEN falhas = falhas + 1.
            WHEN "ERRO" THEN erros = erros + 1.
            WHEN "IGNORADO" THEN ignorados = ignorados + 1.
        END CASE.
        obj:Add("classe", classe).
        obj:Add("caso", nomeCaso).
        obj:Add("status", estado).
        obj:Add("mensagem", msg).
        tempoTexto = REPLACE(n:GET-ATTRIBUTE("time"), ",", ".").
        obj:AddNull("tempo_s").
        IF tempoTexto <> "" THEN DO:
            IF NOT wtcc001ln:CaracteresValidos(tempoTexto, "0123456789.") OR NUM-ENTRIES(tempoTexto, ".") > 2 THEN
                problemas:Add("Tempo XML inválido: " + nomeCaso).
            ELSE DO:
                tempo = DECIMAL(REPLACE(tempoTexto, ".", SESSION:NUMERIC-DECIMAL-POINT)) NO-ERROR.
                IF ERROR-STATUS:ERROR OR tempo = ? THEN problemas:Add("Tempo XML inválido: " + nomeCaso).
                ELSE DO:
                    obj:Set("tempo_s", tempo).
                    somaTempo = somaTempo + tempo.
                    tempos = tempos + 1.
                END.
            END.
        END.
        casos:Add(obj).
        FINALLY:
            IF VALID-HANDLE(filho) THEN DELETE OBJECT filho.
        END FINALLY.
    END METHOD.

    METHOD PRIVATE VOID Percorrer(INPUT n AS HANDLE, INPUT suite AS CHARACTER, INPUT profundidade AS INTEGER):
        DEFINE VARIABLE filho AS HANDLE NO-UNDO.
        DEFINE VARIABLE i AS INTEGER NO-UNDO.
        DEFINE VARIABLE inicio AS INTEGER NO-UNDO.
        DEFINE VARIABLE declarado AS CHARACTER NO-UNDO.
        DEFINE VARIABLE qtd AS INTEGER NO-UNDO.
        DEFINE VARIABLE inicioFalhas AS INTEGER NO-UNDO.
        DEFINE VARIABLE inicioErros AS INTEGER NO-UNDO.
        DEFINE VARIABLE inicioIgnorados AS INTEGER NO-UNDO.
        DEFINE VARIABLE campo AS CHARACTER NO-UNDO.
        DEFINE VARIABLE esperado AS INTEGER NO-UNDO.
        DEFINE VARIABLE j AS INTEGER NO-UNDO.
        IF profundidade > 100 OR casos:Length > 20000 THEN wtcc001ln:Erro("XML excedeu limite de leitura.").
        IF Nome(n) = "testcase" THEN DO:
            Caso(n, suite).
            RETURN.
        END.
        IF Nome(n) = "failure" OR Nome(n) = "error" THEN problemas:Add("Erro de suite: " + Conteudo(n, 0)).
        IF Nome(n) = "testsuite" AND n:GET-ATTRIBUTE("name") <> "" THEN suite = n:GET-ATTRIBUTE("name").
        inicio = casos:Length.
        ASSIGN inicioFalhas = falhas inicioErros = erros inicioIgnorados = ignorados.
        CREATE X-NODEREF filho.
        DO i = 1 TO n:NUM-CHILDREN:
            n:GET-CHILD(filho, i).
            IF filho:SUBTYPE = "ELEMENT" THEN Percorrer(filho, suite, profundidade + 1).
        END.
        IF Nome(n) = "testsuite" OR Nome(n) = "testsuites" THEN DO:
            declarado = n:GET-ATTRIBUTE("tests").
            IF declarado <> "" THEN DO:
                qtd = INTEGER(declarado) NO-ERROR.
                IF ERROR-STATUS:ERROR OR qtd = ? OR qtd <> casos:Length - inicio THEN
                    problemas:Add("Contagem declarada da suite difere dos casos encontrados.").
            END.
            DO j = 1 TO 3:
                campo = ENTRY(j, "failures,errors,skipped").
                declarado = n:GET-ATTRIBUTE(campo).
                IF declarado = "" THEN NEXT.
                esperado = IF j = 1 THEN falhas - inicioFalhas
                           ELSE IF j = 2 THEN erros - inicioErros
                           ELSE ignorados - inicioIgnorados.
                qtd = INTEGER(declarado) NO-ERROR.
                IF ERROR-STATUS:ERROR OR qtd = ? OR qtd <> esperado THEN
                    problemas:Add("Contagem de " + campo + " diverge dos casos encontrados.").
            END.
        END.
        FINALLY:
            IF VALID-HANDLE(filho) THEN DELETE OBJECT filho.
        END FINALLY.
    END METHOD.

    METHOD PUBLIC JsonObject LerXml(INPUT arquivo AS CHARACTER, INPUT esperados AS INTEGER):
        DEFINE VARIABLE doc AS HANDLE NO-UNDO.
        DEFINE VARIABLE raiz AS HANDLE NO-UNDO.
        DEFINE VARIABLE r AS JsonObject NO-UNDO.
        DEFINE VARIABLE identidades AS JsonArray NO-UNDO.
        DEFINE VARIABLE estado AS CHARACTER NO-UNDO.
        ASSIGN casos = NEW JsonArray() problemas = NEW JsonArray()
               aprovados = 0 falhas = 0 erros = 0 ignorados = 0 somaTempo = 0 tempos = 0.
        EMPTY TEMP-TABLE ttIdentidade.
        CREATE X-DOCUMENT doc.
        CREATE X-NODEREF raiz.
        IF NOT doc:LOAD("FILE", arquivo, FALSE) THEN wtcc001ln:Erro("Não foi possível ler results.xml.").
        doc:GET-DOCUMENT-ELEMENT(raiz).
        IF Nome(raiz) <> "testsuite" AND Nome(raiz) <> "testsuites" THEN wtcc001ln:Erro("Raiz XML inesperada.").
        Percorrer(raiz, "", 0).
        IF casos:Length = 0 THEN problemas:Add("XML sem testes.").
        IF esperados > 0 AND casos:Length <> esperados THEN problemas:Add("Quantidade executada difere da quantidade esperada.").
        estado = IF problemas:Length > 0 THEN "INCONCLUSIVO"
                 ELSE IF erros > 0 THEN "ERRO"
                 ELSE IF falhas > 0 THEN "FALHA"
                 ELSE IF ignorados > 0 THEN "INCONCLUSIVO" ELSE "APROVADO".
        r = NEW JsonObject().
        r:Add("status", estado).
        r:Add("total", casos:Length).
        r:Add("aprovados", aprovados).
        r:Add("falhas", falhas).
        r:Add("erros", erros).
        r:Add("ignorados", ignorados).
        r:Add("casos", casos).
        r:Add("problemas", problemas).
        r:AddNull("tempo_testes_s").
        IF tempos = casos:Length AND tempos > 0 THEN r:Set("tempo_testes_s", somaTempo).
        identidades = NEW JsonArray().
        FOR EACH ttIdentidade BY ttIdentidade.chave:
            identidades:Add(ttIdentidade.chave).
        END.
        r:Add("identidades", identidades).
        RETURN r.
        FINALLY:
            IF VALID-HANDLE(raiz) THEN DELETE OBJECT raiz.
            IF VALID-HANDLE(doc) THEN DELETE OBJECT doc.
        END FINALLY.
    END METHOD.

END CLASS.
