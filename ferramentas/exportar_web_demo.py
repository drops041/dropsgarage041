#!/usr/bin/env python3
"""DEMO DO NAVEGADOR (só a garagem, todos os carros) — Drops Garage Racha

Monta uma pasta pronta pra pôr num site:
  index.html / index.js / index.wasm / index.pck   -> a garagem + a G5 Cross (abre rápido)
  carros/<id>.pck.000, .001 ...                    -> cada carro num pacote, baixado só quando você escolhe
  carros/lista.json                                -> {"id": nº de pedaços}
O index.wasm, o index.pck e os pacotes dos carros vão em pedaços de texto (base64, .000.txt, .001.txt...):
a página do link (artifact do Claude) só serve alguns tipos de arquivo e até 20 MB cada. A página junta e
decodifica os pedaços do index.wasm e do index.pck sozinha (script no index.html); o jogo faz o mesmo com os carros.

Uso: python3 ferramentas/exportar_web_demo.py SAIDA [--godot CAMINHO_DO_GODOT] [--carros id1,id2]
Precisa dos modelos de exportação Web (sem threads) do Godot 4.7.2 instalados.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PEDACO = 14 * 1024 * 1024        # bytes de verdade por pedaço (em base64 vira ~18,7 MB, abaixo do limite de 20 MB)
FORA_DA_DEMO = {"lexusnx"}        # licença não comercial (CC BY-NC-SA): não vai pra link compartilhado
NA_BASE = {"saveirog5"}            # carros que já vêm no pacote principal
SEMPRE_BASE = ["saveiro_som"]      # peças que o jogo carrega por fora (trio da Saveiro)

EXCLUIR_BASE = [
    "mapa_cic/*.json", "mapa_cic/blocos/*", "mapa_cic/gerador/*", "mapa_cic/*.bin", "mapa_cic/*.png", "mapa_cic/*.tscn",
    "videos/*", "ferramentas/*", "cenas/historia_abertura.tscn", "imagens/hdri/estacionamento.hdr", "imagens/estudio/*",
    "audio/mega_funk.mp3", "modelos/cenario/posto*", "modelos/cenario/viatura*", "modelos/cenario/delegacia*",
    "modelos/cenario/sala_gamer*", "modelos/cenario/arvores/*", "modelos/cenario/grafite*",
    "modelos/personagens/henry*", "modelos/personagens/jack*", "modelos/personagens/steve*", "modelos/personagens/mulher*",
    "modelos/personagens/soldado*", "modelos/personagens/dancarino*", "modelos/personagens/feliz*",
    "modelos/personagens/mecanico*", "modelos/personagens/motoristas*",
]

OPCOES_WEB = """
[preset.%d.options]

custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=false
vram_texture_compression/for_mobile=true
html/export_icon=true
html/custom_html_shell=""
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=false
"""


def preset(n, nome, filtro, extra):
    return ("[preset.%d]\n\nname=\"%s\"\nplatform=\"Web\"\nrunnable=%s\nadvanced_options=false\ndedicated_server=false\n"
            "custom_features=\"demo\"\n%s\nexport_path=\"\"\npatches=PackedStringArray()\nencryption_include_filters=\"\"\n"
            "encryption_exclude_filters=\"\"\nseed=0\nencrypt_pck=false\nencrypt_directory=false\nscript_export_mode=2\n"
            % (n, nome, "true" if n == 0 else "false", filtro)) + extra + (OPCOES_WEB % n)


def cortar(arq, destino_dir, nome):
    """corta em pedaços de PEDACO bytes, cada um em base64: nome.000.txt, nome.001.txt... devolve quantos"""
    import base64
    n = 0
    with open(arq, "rb") as f:
        while True:
            b = f.read(PEDACO)
            if not b:
                break
            with open(os.path.join(destino_dir, "%s.%03d.txt" % (nome, n)), "wb") as g:
                g.write(base64.b64encode(b))
            n += 1
    return n


# script que entra no index.html: troca o fetch do index.wasm/index.pck pelos pedaços juntados
JUNTAR = """<script>
(function(){var P=%s,S=%s,f0=window.fetch.bind(window);
var T=new Uint8Array(256);for(var k=0;k<64;k++)T['ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'.charCodeAt(k)]=k;
function b64(u){var n=u.length,pad=(u[n-1]==61)+(u[n-2]==61),o=new Uint8Array(n/4*3-pad),j=0;
 for(var i=0;i<n;i+=4){var x=T[u[i]]<<18|T[u[i+1]]<<12|T[u[i+2]]<<6|T[u[i+3]];o[j++]=x>>16;if(j<o.length)o[j++]=x>>8&255;if(j<o.length)o[j++]=x&255}return o}
window.fetch=function(u,o){var s=String(u&&u.url||u),m=s.match(/(index\\.(wasm|pck))(\\?.*)?$/);
 if(!m||!P[m[1]])return f0(u,o);var n=P[m[1]],tipo=m[2]=='wasm'?'application/wasm':'application/octet-stream';
 var base=s.slice(0,s.length-m[0].length);
 var st=new ReadableStream({start:function(c){var i=0;function prox(){if(i>=n){c.close();return}
   f0(base+m[1]+'.'+('00'+i).slice(-3)+'.txt').then(function(r){if(!r.ok)throw new Error('pedaco '+i);return r.arrayBuffer()})
   .then(function(a){c.enqueue(b64(new Uint8Array(a)));i++;prox()}).catch(function(e){c.error(e)})}prox()}});
 return Promise.resolve(new Response(st,{status:200,headers:{'Content-Type':tipo,'Content-Length':String(S[m[1]])}}));};
})();
</script>"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("saida")
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--carros", default="")
    ap.add_argument("--so-base", action="store_true", help="refaz só a página/base (mantém a pasta carros/)")
    a = ap.parse_args()
    saida = os.path.abspath(a.saida)
    carros = json.load(open(os.path.join(RAIZ, "carros.json"), encoding="utf8"))
    ids = [c["id"] for c in carros if os.path.exists(os.path.join(RAIZ, "modelos", "carros", c["id"] + ".glb"))]
    ids = [i for i in ids if i not in FORA_DA_DEMO]
    if a.carros:
        ids = [i for i in ids if i in a.carros.split(",")]
    fora = [i for i in ids if i not in NA_BASE]
    excluir_ids = fora + sorted(FORA_DA_DEMO)
    # arquivos dos carros que ficam fora da base (o modelo e as texturas que saem dele)
    arqs = os.listdir(os.path.join(RAIZ, "modelos", "carros"))
    excl = list(EXCLUIR_BASE)
    for i in excluir_ids:
        rx = re.compile(r"^%s(\.glb|_\d+\.(png|jpg|jpeg|webp))$" % re.escape(i))
        excl += ["modelos/carros/" + f for f in arqs if rx.match(f)]
    presets_orig = os.path.join(RAIZ, "export_presets.cfg")
    guardado = open(presets_orig, encoding="utf8").read() if os.path.exists(presets_orig) else None
    try:
        base = preset(0, "Web Demo Base", 'export_filter="all_resources"\ninclude_filter="*.json"\nexclude_filter="%s"' % ", ".join(excl), "")
        tmp = os.path.join(saida, "_tmp")
        if os.path.exists(saida):
            for f in os.listdir(saida):
                if not (a.so_base and f == "carros"):
                    x = os.path.join(saida, f)
                    shutil.rmtree(x) if os.path.isdir(x) else os.remove(x)
        os.makedirs(tmp)
        os.makedirs(os.path.join(saida, "carros"), exist_ok=True)
        open(presets_orig, "w", encoding="utf8").write(base)
        r = subprocess.run([a.godot, "--headless", "--path", RAIZ, "--export-release", "Web Demo Base", os.path.join(tmp, "index.html")],
                           capture_output=True, text=True)
        if not os.path.exists(os.path.join(tmp, "index.pck")):
            print(r.stdout[-3000:], r.stderr[-3000:])
            sys.exit("falhou a base")
        print("base: %.1f MB" % (os.path.getsize(os.path.join(tmp, "index.pck")) / 1e6))
        lista = {}
        for i in ([] if a.so_base else fora):
            p = preset(0, "Carro", 'export_filter="resources"\nexport_files=PackedStringArray("res://modelos/carros/%s.glb")\ninclude_filter=""\nexclude_filter=""' % i, "")
            open(presets_orig, "w", encoding="utf8").write(p)
            pck = os.path.join(tmp, i + ".pck")
            subprocess.run([a.godot, "--headless", "--path", RAIZ, "--export-pack", "Carro", pck], capture_output=True, text=True)
            if not os.path.exists(pck):
                print("  !! %s não exportou" % i)
                continue
            lista[i] = cortar(pck, os.path.join(saida, "carros"), i + ".pck")
            print("  %-14s %6.1f MB  (%d pedaço%s)" % (i, os.path.getsize(pck) / 1e6, lista[i], "" if lista[i] == 1 else "s"))
        if not a.so_base:
            json.dump(lista, open(os.path.join(saida, "carros", "lista.json"), "w"))
    finally:
        if guardado is not None:
            open(presets_orig, "w", encoding="utf8").write(guardado)
    # página: wasm e pck em pedaços, sem gravar no IndexedDB (a página pode rodar num quadro sem ele)
    partes, tam = {}, {}
    for nome in ["index.wasm", "index.pck"]:
        arq = os.path.join(tmp, nome)
        tam[nome] = os.path.getsize(arq)
        partes[nome] = cortar(arq, saida, nome)   # sempre em pedaços de texto (o .pck nem é tipo servido)
    for f in os.listdir(tmp):
        if f.startswith("index.") and f not in ("index.wasm", "index.pck", "index.html"):
            shutil.copy(os.path.join(tmp, f), os.path.join(saida, f))
    html = open(os.path.join(tmp, "index.html"), encoding="utf8").read()
    html = html.replace('GODOT_CONFIG = {"args":[],', 'GODOT_CONFIG = {"args":[],"persistentPaths":[],', 1)
    html = html.replace("<script src=\"index.js\"></script>", (JUNTAR % (json.dumps(partes), json.dumps(tam))) + "\n<script src=\"index.js\"></script>")
    if "persistentPaths\":[]" not in html or "window.fetch=function" not in html:
        print("  !! atenção: não achei onde mexer no index.html (persistentPaths/index.js)")
    open(os.path.join(saida, "index.html"), "w", encoding="utf8").write(html)
    shutil.rmtree(tmp)
    total = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(saida) for f in fs)
    print("pronto: %s  (%.0f MB no total, %d arquivos)" % (saida, total / 1e6, sum(len(fs) for _, _, fs in os.walk(saida))))


if __name__ == "__main__":
    main()
