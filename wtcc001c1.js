/* Mesmo fluxo do exemplo: POST para a URL da tela + vpad_exec.
   O navegador cadastra entradas; somente o Progress executa as regras. */
(function () {
    "use strict";
    const $id = id => document.getElementById(id);
    const estado = { revisao: 0, baterias: [], cenarios: [], execucoes: [], ambiente: {}, anexos: [] };
    let revisaoBateria = 0, revisaoCenario = 0, resultado = null, fonte = "", selecionada = "";
    let ocupado = false, consultando = false, timer = null;
    const ativos = s => s === "NA FILA" || s === "EXECUTANDO";
    function aviso(texto, tipo) {
        $id("aviso").textContent = texto;
        $id("aviso").className = "aviso " + (tipo || "");
        $id("aviso").hidden = !texto;
    }
    function jsonAscii(obj) {
        return JSON.stringify(obj).replace(/[\u007f-\uffff]/g, c => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"));
    }
    function latin1(texto) {
        for (let i = 0; i < texto.length; i++) if (texto.charCodeAt(i) > 255) throw new Error("Use caracteres disponíveis em ISO-8859-1.");
        return Uint8Array.from(texto, c => c.charCodeAt(0));
    }
    async function ajax(acao, obj) {
        const json = jsonAscii(obj || {});
        if (json.length > 30000) throw new Error("Os dados excedem o limite de 30.000 caracteres da requisição. Reduza os textos.");
        const url = new URL(window.location.href);
        url.hash = "";
        // Preserva a sessao na URL; os parametros da operacao seguem no POST.
        ["vpad_exec", "tcc_request", "vjson"].forEach(nome => url.searchParams.delete(nome));
        return new Promise((resolve, reject) => {
            $.ajax({
                type: "POST",
                url: url.href,
                data: "vpad_exec=" + encodeURIComponent(acao) + "&tcc_request=1&vjson=" + encodeURIComponent(json),
                contentType: "application/x-www-form-urlencoded; charset=ISO-8859-1",
                dataType: "text", timeout: 30000, headers: { "X-TCC-Request": "1" },
                beforeSend: xhr => xhr.overrideMimeType("application/json; charset=ISO-8859-1"),
                success: texto => {
                    try {
                        const r = JSON.parse(texto);
                        if (r.status !== 0) throw new Error(r.msg || "A operação não foi concluída.");
                        resolve(r.data);
                    } catch (e) { reject(e instanceof SyntaxError ? new Error("Resposta inválida do Progress. Verifique sessão, configuração e logs do agente.") : e); }
                },
                error: (_, status) => reject(new Error(status === "timeout" ? "A consulta excedeu o tempo. Atualize o histórico antes de tentar novamente." : "Não foi possível consultar o Progress. Verifique a sessão."))
            });
        });
    }
    async function acao(fn) {
        if (ocupado) return;
        ocupado = true;
        $id("areaLoad").hidden = false;
        try { await fn(); } catch (e) { aviso(e.message || String(e), "erro"); }
        finally { ocupado = false; $id("areaLoad").hidden = true; }
    }
    function opcoes(id, lista, valor, vazio) {
        const select = $id(id);
        select.replaceChildren();
        if (vazio) select.add(new Option(vazio, ""));
        lista.forEach(v => select.add(new Option(typeof v === "string" ? v : v.descricao, typeof v === "string" ? v : String(v.id))));
        if (valor !== undefined && [...select.options].some(o => o.value === String(valor))) select.value = String(valor);
    }
    function celula(tr, texto, classe) {
        const td = document.createElement("td");
        td.textContent = texto == null ? "" : String(texto);
        if (classe) td.className = classe;
        tr.appendChild(td);
        return td;
    }
    function badge(tr, status) {
        const td = celula(tr, "");
        const span = document.createElement("span");
        span.className = "status " + String(status).replace(/[^A-Z]/g, "");
        span.textContent = status;
        td.appendChild(span);
    }
    function linhaLista(tbody, cols, callback, selected) {
        const tr = document.createElement("tr");
        tr.className = "registro" + (selected ? " escolhida" : "");
        cols.forEach((v, i) => {
            if (i === 0) {
                const td = celula(tr, "");
                const button = document.createElement("button");
                button.type = "button";
                button.textContent = String(v);
                button.addEventListener("click", e => { e.stopPropagation(); callback(); });
                td.appendChild(button);
            } else celula(tr, v);
        });
        tr.addEventListener("click", callback);
        tbody.appendChild(tr);
        return tr;
    }
    function vazio(id, colspan, texto) {
        const tr = document.createElement("tr"), td = celula(tr, texto, "vazio");
        td.colSpan = colspan;
        $id(id).appendChild(tr);
    }
    function renderBaterias() {
        const tbody = $id("lista-baterias"); tbody.replaceChildren();
        estado.baterias.forEach(b => linhaLista(tbody, [b.id, b.descricao, b.tipo === "CENARIOS" ? "Cenários" : "ABLUnit"], () => carregarBateria(b.id), b.id === Number($id("b-id").value)));
        if (!estado.baterias.length) vazio("lista-baterias", 3, "Nenhuma bateria cadastrada.");
        $id("resumo-baterias").textContent = estado.baterias.length + " baterias";
        tipoBateria();
    }
    function renderCenarios() {
        const filtro = Number($id("c-filtro-bateria").value);
        const lista = estado.cenarios.filter(c => !filtro || c.bateria_id === filtro);
        const tbody = $id("lista-cenarios"); tbody.replaceChildren();
        lista.forEach(c => linhaLista(tbody, [c.id, c.descricao, c.modelo, c.ativo ? "Sim" : "Não"], () => carregarCenario(c.id), c.id === Number($id("c-id").value)));
        if (!lista.length) vazio("lista-cenarios", 4, "Nenhum cenário para esta bateria.");
        $id("resumo-cenarios").textContent = lista.length + " cenários";
    }
    function renderExecucoes() {
        const tbody = $id("lista-execucoes"); tbody.replaceChildren();
        [...estado.execucoes].reverse().forEach(e => {
            const tr = linhaLista(tbody, [e.descricao], () => acao(() => consultarResultado(e.id)), e.id === selecionada);
            const sub = document.createElement("span");
            sub.className = "secundario"; sub.textContent = e.criado_em + " · " + e.usuario + (e.anexo ? " · fonte " + e.anexo.nome : "");
            tr.firstChild.appendChild(sub);
            badge(tr, e.status);
        });
        if (!estado.execucoes.length) vazio("lista-execucoes", 2, "Nenhuma execução registrada.");
    }
    function ambiente() {
        const a = estado.ambiente;
        $id("ambiente-resumo").textContent = (a.nome || "Ambiente") + " · " + (a.habilitado ? "Execução habilitada" : "Execução aguardando configuração");
        const rows = [
            ["Ambiente", a.nome], ["Versão do agente web", a.proversion_agente],
            ["Executável AVM", a.avm], ["Arquivo .pf dos testes", a.pf], ["Diretório dos testes", a.projeto],
            ["AVM localizada", a.avm_existe ? "Sim" : "Não"], [".pf localizado", a.pf_existe ? "Sim" : "Não"],
            ["Executor localizado", a.launcher_existe ? "Sim" : "Não"], ["Execução habilitada", a.habilitado ? "Sim" : "Não"]
        ];
        $id("lista-ambiente").replaceChildren();
        rows.forEach(row => { const tr = document.createElement("tr"); row.forEach(v => celula(tr, v)); $id("lista-ambiente").appendChild(tr); });
    }
    function aplicar(d) {
        const a = estado.ambiente;
        Object.assign(estado, d);
        estado.ambiente = d.ambiente || a;
        const filtro = $id("c-filtro-bateria").value, bateria = $id("c-bateria").value;
        const classes = estado.ambiente.classes || [], testes = estado.ambiente.testes || [];
        opcoes("b-classe", classes, $id("b-classe").value, classes.length ? undefined : "Nenhuma classe configurada");
        opcoes("b-teste", testes, $id("b-teste").value, testes.length ? undefined : "Nenhum teste configurado");
        $id("b-classe").disabled = !classes.length;
        $id("b-teste").disabled = !testes.length;
        const cadastraveis = estado.baterias.filter(b => b.tipo === "CENARIOS");
        opcoes("c-filtro-bateria", cadastraveis, filtro, "Todas as baterias");
        opcoes("c-bateria", cadastraveis, bateria, "Selecione");
        renderBaterias(); renderCenarios(); renderExecucoes(); ambiente(); renderFontes(); agendar();
    }
    function tipoBateria() {
        const existente = $id("b-tipo").value === "ABLUNIT";
        $id("b-grupo-classe").hidden = existente;
        $id("b-grupo-teste").hidden = !existente;
        $id("bt-excluir-bateria").disabled = Number($id("b-id").value) === 0;
        $id("bt-fonte").disabled = existente || Number($id("b-id").value) === 0;
        $id("bt-executar").disabled = !estado.ambiente.habilitado || Number($id("b-id").value) === 0 || estado.execucoes.some(e => ativos(e.status));
    }
    function renderFontes(valor) {
        const atual = valor !== undefined ? valor : $id("b-fonte").value;
        const bat = estado.baterias.find(x => x.id === Number($id("b-id").value));
        const classe = bat && bat.tipo === "CENARIOS" ? String(bat.classe || "").toLowerCase() : "";
        const lista = (estado.anexos || []).map(a => ({ id: a.id, descricao: (classe && String(a.classe || "").toLowerCase() !== classe ? "(outra classe) " : "") + a.nome + " · " + String(a.criado_em).substring(0, 16) + " · " + String(a.sha256).substring(0, 8) }));
        opcoes("b-fonte", lista, atual, "Fonte instalado no servidor");
        $id("bt-excluir-anexo").disabled = !$id("b-fonte").value;
    }
    async function anexar(arquivo) {
        if (!arquivo) return;
        if (!/^[A-Za-z0-9_-]+\.(cls|p)$/i.test(arquivo.name)) throw new Error("Use um arquivo .cls ou .p com nome simples (letras, números, _ e -).");
        if (/^wtcc001/i.test(arquivo.name)) throw new Error("Fontes do laboratório não podem ser anexados.");
        if (!arquivo.size || arquivo.size > 2000000) throw new Error("O fonte deve ter entre 1 e 2.000.000 bytes.");
        const bytes = new Uint8Array(await arquivo.arrayBuffer());
        let texto = "";
        for (let i = 0; i < bytes.length; i += 8192) texto += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
        const info = lerMetodos(texto);
        let pos = 0, parte = 0, upload = "", r = null;
        while (pos < texto.length) {
            let n = Math.min(20000, texto.length - pos), obj;
            for (;;) {
                const fim = pos + n >= texto.length;
                obj = { upload, parte: parte + 1, nome: arquivo.name, tamanho: bytes.length, fim, conteudo: texto.substr(pos, n) };
                if (fim) obj.metodos = info.metodos;
                if (jsonAscii(obj).length <= 28000 || n <= 200) break;
                n = Math.floor(n * 0.7);
            }
            r = await ajax("p_anexo_parte", obj);
            upload = r.upload; parte++; pos += n;
            aviso("Enviando " + arquivo.name + ": " + Math.round(pos * 100 / texto.length) + "%", "");
        }
        estado.anexos = r.anexos || [];
        renderFontes(r.anexo ? r.anexo.id : "");
        if ($id("c-modelo").value === "metodo") renderMetodos();
        aviso("Fonte anexado: " + arquivo.name + " · SHA-256 " + (r.anexo ? r.anexo.sha256.substring(0, 12) : "") + " · " + (r.anexo && r.anexo.metodos ? r.anexo.metodos.length : 0) + " método(s) público(s) disponível(is) para cenários" + (info.instanciavel ? "" : " (sem construtor público sem parâmetros: só métodos estáticos)") + ". Ele já está selecionado em Fonte usado na execução.", "sucesso");
    }
    async function excluirAnexo() {
        const id = $id("b-fonte").value;
        if (!id) return;
        if (!window.confirm("Excluir o fonte anexado? As execuções já feitas mantêm a própria cópia.")) return;
        const r = await ajax("p_anexo_excluir", { id });
        estado.anexos = r.anexos || [];
        renderFontes("");
        aviso("Fonte anexado excluído.", "sucesso");
    }
    function tipoAbl(t) {
        t = String(t || "").toLowerCase();
        if (t === "int64") return "INT64";
        if (t === "longchar") return "LONGCHAR";
        if (t === "date") return "DATE";
        for (const [nome, minimo, tipo] of [["character", 4, "CHARACTER"], ["integer", 3, "INTEGER"], ["decimal", 3, "DECIMAL"], ["logical", 3, "LOGICAL"]])
            if (t.length >= minimo && nome.startsWith(t)) return tipo;
        return "";
    }
    function lerMetodos(texto) {
        const limpo = texto.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/\/\/[^\n]*/g, " ");
        const metodos = [];
        const re = /\bmethod\s+((?:(?:public|protected|private|static|override|final|abstract)\s+)+)([\w.-]+)\s+([\w-]+)\s*\(([^)]*)\)/gi;
        let m;
        while ((m = re.exec(limpo))) {
            const mods = m[1].toLowerCase().split(/\s+/);
            const retorno = tipoAbl(m[2]);
            if (!mods.includes("public") || !retorno) continue;
            const tipos = [], nomes = [];
            let ok = true;
            m[4].split(",").map(p => p.trim()).filter(p => p).forEach(p => {
                const q = /^(?:(input)\s+)?([\w-]+)\s+as\s+([\w.-]+)\s*(no-undo)?$/i.exec(p.replace(/\s+/g, " "));
                const tipo = q ? tipoAbl(q[3]) : "";
                if (!tipo) ok = false; else { tipos.push(tipo); nomes.push(q[2]); }
            });
            if (ok) metodos.push({ nome: m[3], estatico: mods.includes("static"), retorno, tipos, nomes });
        }
        const ctors = [...limpo.matchAll(/\bconstructor\s+((?:(?:public|protected|private|static)\s+)+)[\w.-]+\s*\(([^)]*)\)/gi)];
        const instanciavel = !ctors.length || ctors.some(c => /\bpublic\b/i.test(c[1]) && !/\bstatic\b/i.test(c[1]) && !c[2].trim());
        return { metodos: metodos.filter(x => x.estatico || instanciavel).slice(0, 150), instanciavel };
    }
    function classeCenario() {
        const b = estado.baterias.find(x => x.id === Number($id("c-bateria").value));
        return b && b.tipo === "CENARIOS" ? String(b.classe || "") : "";
    }
    function atualizarModelos(valor) {
        const classe = classeCenario().toLowerCase();
        const lista = [{ id: "metodo", descricao: "Chamar método da classe" }];
        if (!classe || classe === "clsexemplo") lista.push({ id: "addWhere", descricao: "addWhere - combina condições (classe de exemplo)" }, { id: "setErro", descricao: "setErro / msgErros - mensagens (classe de exemplo)" });
        opcoes("c-modelo", lista, valor !== undefined ? valor : $id("c-modelo").value);
    }
    function metodosDaClasse(classe) {
        const lista = (estado.anexos || []).filter(a => a.classe && a.classe.toLowerCase() === classe.toLowerCase() && a.metodos && a.metodos.length);
        return lista.length ? lista[lista.length - 1] : null;
    }
    function chaveMetodo(x) { return String(x.nome || "").toLowerCase() + "|" + (x.tipos || []).join(",") + "|" + (x.estatico ? 1 : 0); }
    function assinatura(x) {
        return x.nome + "(" + (x.tipos || []).map((t, i) => ((x.nomes || [])[i] ? x.nomes[i] + " " : "") + t).join(", ") + ") : " + x.retorno + (x.estatico ? " · estático" : "");
    }
    let metodosAtuais = [];
    function metodoSelecionado() { return metodosAtuais[Number($id("c-metodo-nome").value)] || null; }
    function renderMetodos(entradas) {
        const classe = classeCenario();
        const anexo = classe ? metodosDaClasse(classe) : null;
        const salvo = entradas && entradas.metodo ? { nome: entradas.metodo, estatico: !!entradas.estatico, retorno: entradas.retorno, tipos: entradas.tipos || [], nomes: entradas.nomes || [] } : null;
        metodosAtuais = anexo ? anexo.metodos.slice() : [];
        if (salvo && !metodosAtuais.some(x => chaveMetodo(x) === chaveMetodo(salvo))) metodosAtuais.unshift(salvo);
        const alvo = salvo ? metodosAtuais.findIndex(x => chaveMetodo(x) === chaveMetodo(salvo)) : Number($id("c-metodo-nome").value);
        opcoes("c-metodo-nome", metodosAtuais.map((x, i) => ({ id: i, descricao: assinatura(x) })), alvo >= 0 ? alvo : undefined, metodosAtuais.length ? undefined : "Nenhum método disponível");
        $id("c-metodo-ajuda").textContent = !classe ? "Selecione uma bateria do tipo Cenários."
            : (anexo ? "Métodos públicos lidos de " + anexo.nome + " (" + String(anexo.sha256).substring(0, 8) + ")." : "Anexe o fonte " + classe + ".cls na aba Baterias para listar os métodos públicos.")
            + " O método é executado de verdade nos bancos do .pf do laboratório: evite métodos que gravam ou excluem dados. Datas em dd/mm/aaaa; decimais com vírgula ou ponto; lógicos yes/no; ? = valor desconhecido.";
        renderArgumentos(salvo ? entradas.argumentos || [] : undefined);
    }
    function renderArgumentos(valores) {
        const area = $id("c-argumentos"), x = metodoSelecionado();
        const atuais = valores || [...area.querySelectorAll("input")].map(i => i.value);
        area.replaceChildren();
        if (!x) return;
        (x.tipos || []).forEach((tipo, i) => {
            const div = document.createElement("div");
            div.className = "material-textfield campo-texto";
            const input = document.createElement("input");
            input.id = "c-arg-" + i; input.placeholder = " "; input.maxLength = 8000;
            input.value = atuais[i] !== undefined ? atuais[i] : "";
            const label = document.createElement("label");
            label.className = "label"; label.htmlFor = input.id;
            label.textContent = ((x.nomes || [])[i] || "parâmetro " + (i + 1)) + " (" + tipo + ")";
            div.append(input, label);
            area.appendChild(div);
        });
    }
    function modeloCenario(entradas) {
        const m = $id("c-modelo").value;
        ["addWhere", "setErro", "metodo"].forEach(v => $id("c-" + v).hidden = v !== m);
        if (m === "metodo") renderMetodos(entradas);
        $id("bt-excluir-cenario").disabled = Number($id("c-id").value) === 0;
    }
    function carregarBateria(id) {
        const b = estado.baterias.find(b => b.id === id);
        revisaoBateria = estado.revisao;
        $id("form-bateria").reset(); $id("b-id").value = b ? b.id : 0;
        if (b) {
            $id("b-descricao").value = b.descricao; $id("b-tipo").value = b.tipo;
            if (b.classe) $id("b-classe").value = b.classe;
            if (b.teste) $id("b-teste").value = b.teste;
            $id("b-esperados").value = b.esperados || 10;
        }
        renderBaterias(); renderFontes();
    }
    function carregarCenario(id) {
        const c = estado.cenarios.find(c => c.id === id);
        revisaoCenario = estado.revisao;
        $id("form-cenario").reset(); $id("c-id").value = c ? c.id : 0;
        if (c) {
            $id("c-descricao").value = c.descricao; $id("c-bateria").value = c.bateria_id;
            atualizarModelos(c.modelo); $id("c-ativo").checked = c.ativo;
            const e = c.entradas;
            $id("c-where").value = e.where || ""; $id("c-condicao").value = e.condicao || "";
            $id("c-mensagens").value = (e.mensagens || []).join("\n");
            $id("c-esperado").value = e.esperado;
        } else if ($id("c-filtro-bateria").value) $id("c-bateria").value = $id("c-filtro-bateria").value;
        if (!c) atualizarModelos();
        modeloCenario(c ? c.entradas : undefined); renderCenarios();
    }
    function aba(nome) {
        document.querySelectorAll(".conteudo-aba").forEach(el => el.hidden = el.id !== "aba-" + nome);
        document.querySelectorAll(".aba").forEach(el => el.classList.toggle("selecionada", el.dataset.aba === nome));
    }
    async function atualizar(reset) {
        if (reset || !estado.ambiente.nome) {
            try {
                aplicar({ ambiente: await ajax("p_ambiente", {}) });
            } catch (e) {
                $id("ambiente-resumo").textContent = "Não foi possível carregar as opções do Progress.";
                if (!estado.ambiente.nome) {
                    opcoes("b-classe", [], "", "Falha ao consultar o Progress");
                    opcoes("b-teste", [], "", "Falha ao consultar o Progress");
                    $id("b-classe").disabled = true; $id("b-teste").disabled = true;
                }
                throw new Error("Falha ao consultar o ambiente: " + e.message + " Confira a publicação e a compilação de wtcc001c1.p e wtcc001ln.cls.");
            }
        }
        try { aplicar(await ajax("p_listar", {})); }
        catch (e) { throw new Error("As opções foram consultadas, mas os cadastros não carregaram: " + e.message); }
        if (reset) { carregarBateria(0); carregarCenario(0); }
    }
    async function gravarBateria() {
        latin1($id("b-descricao").value);
        const b = { id: Number($id("b-id").value), descricao: $id("b-descricao").value, tipo: $id("b-tipo").value,
            classe: $id("b-classe").value, teste: $id("b-teste").value, esperados: Number($id("b-esperados").value) };
        if (b.tipo === "CENARIOS" && !b.classe) throw new Error("Nenhuma classe selecionada. Confira allowed_business_classes em /opt/ablunitlab/app/wtcc001.json e clique em Atualizar.");
        if (b.tipo === "ABLUNIT" && !b.teste) throw new Error("Nenhum teste selecionado. Confira allowed_test_classes em /opt/ablunitlab/app/wtcc001.json e clique em Atualizar.");
        aplicar(await ajax("p_gravar_bateria", { revisao: revisaoBateria, bateria: b }));
        const id = b.id || Math.max(...estado.baterias.map(b => b.id));
        carregarBateria(id); carregarCenario(Number($id("c-id").value)); aviso("Bateria gravada.", "sucesso");
    }
    async function gravarCenario() {
        const m = $id("c-modelo").value;
        const e = { esperado: $id("c-esperado").value };
        if (m === "addWhere") Object.assign(e, { where: $id("c-where").value, condicao: $id("c-condicao").value });
        if (m === "setErro") e.mensagens = $id("c-mensagens").value === "" ? [] : $id("c-mensagens").value.replace(/\r/g, "").split("\n");
        if (m === "metodo") {
            const x = metodoSelecionado();
            if (!x) throw new Error("Selecione o método. Para listar os métodos, anexe o fonte da classe na aba Baterias.");
            const tipos = x.tipos || [];
            Object.assign(e, { metodo: x.nome, estatico: !!x.estatico, retorno: x.retorno, tipos,
                nomes: tipos.map((_, i) => (x.nomes || [])[i] || "p" + (i + 1)),
                argumentos: tipos.map((_, i) => $id("c-arg-" + i) ? $id("c-arg-" + i).value : "") });
        }
        [e.esperado, e.where || "", e.condicao || "", e.texto || "", ...(e.mensagens || []), ...(e.argumentos || []), $id("c-descricao").value].forEach(latin1);
        const c = { id: Number($id("c-id").value), bateria_id: Number($id("c-bateria").value),
            descricao: $id("c-descricao").value, modelo: m, ativo: $id("c-ativo").checked, entradas: e };
        if (!c.bateria_id) throw new Error("Selecione uma bateria.");
        aplicar(await ajax("p_gravar_cenario", { revisao: revisaoCenario, cenario: c }));
        carregarCenario(c.id || Math.max(...estado.cenarios.map(c => c.id)));
        carregarBateria(Number($id("b-id").value)); aviso("Cenário gravado.", "sucesso");
    }
    async function excluir(chave) {
        const isB = chave === "baterias", id = Number($id(isB ? "b-id" : "c-id").value);
        if (!id) return;
        if (!window.confirm(isB ? "Excluir a bateria e seus cenários? O histórico será preservado." : "Excluir este cenário?")) return;
        aplicar(await ajax("p_excluir", { revisao: isB ? revisaoBateria : revisaoCenario, cadastro: chave, id }));
        carregarBateria(0); carregarCenario(0); aviso("Registro excluído.", "sucesso");
    }
    function dialogo(titulo, texto, baixar) {
        $id("dialogo-titulo").textContent = titulo; $id("dialogo-texto").textContent = texto;
        $id("bt-baixar-fonte").hidden = !baixar;
        if (!$id("dialogo").open) $id("dialogo").showModal();
    }
    async function verFonte() {
        const r = await ajax("p_fonte", { bateria_id: Number($id("b-id").value) });
        fonte = r.codigo; dialogo("Fonte ABLUnit gerado · entradas lidas do JSON da rodada", fonte, true);
    }
    async function executar() {
        const r = await ajax("p_executar", { revisao: estado.revisao, bateria_id: Number($id("b-id").value), repeticoes: Number($id("b-repeticoes").value), anexo_id: $id("b-fonte").value });
        selecionada = r.id;
        await atualizar(false); aba("execucoes"); await consultarResultado(r.id);
        aviso("Execução solicitada ao Progress. Acompanhe o histórico.", "sucesso");
    }
    async function consultarResultado(id) {
        resultado = await ajax("p_resultado", { id });
        selecionada = id; renderExecucoes();
        $id("r-titulo").textContent = resultado.descricao + " · " + resultado.status + (resultado.anexo ? " · fonte " + resultado.anexo.nome + " (" + String(resultado.anexo.sha256).substring(0, 8) + ")" : " · fonte instalado");
        const n = $id("r-repeticao").value;
        opcoes("r-repeticao", (resultado.medidas || []).map(m => ({ id: m.repeticao, descricao: "Rodada " + m.repeticao })), n);
        if (!$id("r-repeticao").options.length) $id("r-repeticao").add(new Option("Aguardando", ""));
        renderResultado();
    }
    function medida() { return resultado && (resultado.medidas || []).find(m => m.repeticao === Number($id("r-repeticao").value)); }
    function renderResultado() {
        const m = medida();
        ["total", "aprovados", "falhas", "erros", "ignorados"].forEach(k => $id("r-" + k).textContent = m && m[k] !== undefined ? String(m[k]) : "-");
        const problemas = [...(resultado ? resultado.problemas || [] : []), ...(m ? m.problemas || [] : [])];
        if (m && m.mensagem) problemas.push(m.mensagem);
        $id("r-problemas").textContent = problemas.join("\n"); $id("r-problemas").hidden = !problemas.length;
        $id("lista-resultados").replaceChildren();
        (m ? m.casos || [] : []).forEach(c => {
            const tr = document.createElement("tr"), td = celula(tr, c.caso);
            const sub = document.createElement("span"); sub.className = "secundario"; sub.textContent = c.classe; td.appendChild(sub);
            badge(tr, c.status); celula(tr, c.tempo_s == null ? "-" : c.tempo_s); celula(tr, c.mensagem);
            $id("lista-resultados").appendChild(tr);
        });
        if (!m || !m.casos || !m.casos.length) vazio("lista-resultados", 4, m && m.status === "ERRO" ? "Execução sem casos válidos. Consulte os logs." : "Aguardando resultados do ABLUnit.");
        $id("r-tempo").textContent = m ? "Testes: " + (m.tempo_testes_s == null ? "não informado" : m.tempo_testes_s + " s") + " · Processo: " + m.duracao_parede_s + " s · " + m.status : "Aguardando resultados";
        $id("r-resumo").textContent = resultado ? "Testes esperados: " + resultado.esperados + " · Concluídas: " + resultado.concluidas + "/" + resultado.repeticoes + " · Média dos testes: " + (resultado.media_tempo_testes_s == null ? "-" : resultado.media_tempo_testes_s + " s") : "";
        $id("bt-logs").disabled = !resultado; $id("bt-csv").disabled = !resultado || !(resultado.medidas || []).length;
    }
    async function logs() {
        if (!resultado) return;
        const r = await ajax("p_logs", { id: resultado.id, repeticao: Number($id("r-repeticao").value) || 1 });
        dialogo("Logs da execução", "LAUNCHER\n" + r.launcher + "\nAVM\n" + r.avm + "\nABLUNIT\n" + r.ablunit, false);
    }
    function baixar(nome, dados, mime) {
        const url = URL.createObjectURL(new Blob([dados], { type: mime }));
        const a = document.createElement("a"); a.href = url; a.download = nome; a.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
    }
    function csvValor(v) {
        let t = v == null ? "" : String(v);
        if (/^[=+@-]/.test(t)) t = "'" + t;
        return '"' + t.replace(/"/g, '""') + '"';
    }
    function csv() {
        if (!resultado) return;
        const rows = [["execucao", "bateria", "repeticao", "situacao_repeticao", "caso", "classe", "situacao_caso", "tempo_caso_s", "tempo_testes_s", "duracao_processo_s", "mensagem", "fonte", "fonte_sha256"]];
        (resultado.medidas || []).forEach(m => {
            const casos = m.casos && m.casos.length ? m.casos : [{}];
            casos.forEach(c => rows.push([resultado.id, resultado.descricao, m.repeticao, m.status, c.caso, c.classe, c.status, c.tempo_s, m.tempo_testes_s, m.duracao_parede_s, c.mensagem || m.mensagem, resultado.anexo ? resultado.anexo.nome : "instalado", resultado.anexo ? resultado.anexo.sha256 : ""]));
        });
        baixar("ABLUnit_" + resultado.id + ".csv", "\ufeff" + rows.map(r => r.map(csvValor).join(";")).join("\r\n"), "text/csv;charset=utf-8");
    }
    function agendar() {
        clearTimeout(timer);
        if (estado.execucoes.some(e => ativos(e.status))) timer = setTimeout(poll, 2500);
    }
    async function poll() {
        if (consultando || ocupado) { timer = setTimeout(poll, 2500); return; }
        consultando = true;
        try { await atualizar(false); if (selecionada) await consultarResultado(selecionada); }
        catch (e) { aviso(e.message, "erro"); timer = setTimeout(poll, 5000); }
        finally { consultando = false; }
    }
    document.addEventListener("DOMContentLoaded", () => {
        document.querySelectorAll(".aba").forEach(el => el.addEventListener("click", () => aba(el.dataset.aba)));
        $id("b-tipo").addEventListener("change", tipoBateria);
        $id("c-modelo").addEventListener("change", () => modeloCenario());
        $id("c-bateria").addEventListener("change", () => { atualizarModelos(); modeloCenario(); });
        $id("c-metodo-nome").addEventListener("change", () => renderArgumentos([]));
        $id("c-filtro-bateria").addEventListener("change", renderCenarios);
        $id("bt-nova-bateria").addEventListener("click", () => carregarBateria(0));
        $id("bt-novo-cenario").addEventListener("click", () => carregarCenario(0));
        $id("form-bateria").addEventListener("submit", e => { e.preventDefault(); acao(gravarBateria); });
        $id("form-cenario").addEventListener("submit", e => { e.preventDefault(); acao(gravarCenario); });
        $id("bt-excluir-bateria").addEventListener("click", () => acao(() => excluir("baterias")));
        $id("bt-excluir-cenario").addEventListener("click", () => acao(() => excluir("cenarios")));
        $id("bt-atualizar").addEventListener("click", () => acao(() => atualizar(true)));
        $id("bt-fonte").addEventListener("click", () => acao(verFonte));
        $id("bt-executar").addEventListener("click", () => acao(executar));
        $id("bt-logs").addEventListener("click", () => acao(logs));
        $id("bt-csv").addEventListener("click", csv);
        $id("bt-anexar").addEventListener("click", () => $id("arquivo-fonte").click());
        $id("arquivo-fonte").addEventListener("change", () => { const arquivo = $id("arquivo-fonte").files[0]; $id("arquivo-fonte").value = ""; acao(() => anexar(arquivo)); });
        $id("b-fonte").addEventListener("change", () => renderFontes());
        $id("bt-excluir-anexo").addEventListener("click", () => acao(excluirAnexo));
        $id("r-repeticao").addEventListener("change", renderResultado);
        $id("bt-fechar-dialogo").addEventListener("click", () => $id("dialogo").close());
        $id("bt-baixar-fonte").addEventListener("click", () => acao(async () => baixar("wtcc001gerado.cls", latin1(fonte), "application/octet-stream")));
        renderResultado(); acao(() => atualizar(true));
    });
})();
