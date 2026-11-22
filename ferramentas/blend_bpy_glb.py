"""Converte um .blend em .glb usando o Blender de verdade como módulo Python (pip install bpy).
Conserta o que o exportador do glTF não entende: tira os REROUTE do caminho das texturas, liga a cor
direto quando ela passa por um MIX (cor x AO), religa a cor base que estava solta e completa imagens
que faltam com as do textures.zip. Depois rode ferramentas/imagens_jpg.py pra deixar leve.
Uso: python3 -I ferramentas/blend_bpy_glb.py entrada.blend saida.glb pasta_texturas
(foi assim que entrou a oficina nova: modelos/cenario/oficina_nova/oficina_nova.glb)"""
import bpy, sys, os
src, dst, texdir = sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=src, load_ui=False, use_scripts=False)
# imagens que faltam no .blend (parede de concreto): pega as do textures.zip
falta = {"Material_Base_color.png.004": "mat_concrete_wall_BaseColor.png", "Material_Normal_OpenGL.png.004": "mat_concrete_wall_Normal.png",
         "Material_Roughness.png.004": "mat_concrete_wall_Roughness.png"}
for nome, arq in falta.items():
    im = bpy.data.images.get(nome)
    if im:
        im.filepath = os.path.join(texdir, arq)
        im.reload()
        im.pack()
for im in bpy.data.images:
    if im.size[0] > 1024 and im.name != 'potsdamer_platz_4k.exr':
        im.scale(1024, max(1, int(im.size[1] * 1024 / im.size[0])))
for m in bpy.data.materials:
    if not m.node_tree: continue
    nt = m.node_tree
    # tira os REROUTE (o exportador do glTF não segue) ligando direto
    for n in list(nt.nodes):
        if n.type == 'REROUTE':
            ins = [l.from_socket for l in nt.links if l.to_node == n]
            outs = [l.to_socket for l in nt.links if l.from_node == n]
            for o in outs:
                if ins: nt.links.new(ins[0], o)
            nt.nodes.remove(n)
    # MIX (cor x AO) na cor base: liga a textura de cor direto
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    for n in list(nt.nodes):
        if n.type == 'MIX' and bsdf:
            a = [l for l in nt.links if l.to_node == n and l.to_socket.name == 'A']
            if a: nt.links.new(a[0].from_socket, bsdf.inputs['Base Color'])
    # cor base da estante de ferramentas não estava ligada
    if bsdf and not bsdf.inputs['Base Color'].is_linked:
        for n in nt.nodes:
            if n.type == 'TEX_IMAGE' and n.image and ('Base_color' in n.image.name or 'BaseColor' in n.image.name):
                nt.links.new(n.outputs['Color'], bsdf.inputs['Base Color'])
    for n in nt.nodes:
        if n.type == 'MAPPING':
            print(m.name, 'mapping', tuple(n.inputs['Scale'].default_value), tuple(n.inputs['Location'].default_value))
for o in list(bpy.data.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_image_format='AUTO',
    export_apply=True, export_yup=True, export_lights=False, export_cameras=False)
