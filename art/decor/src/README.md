# Décor, gifts and leaf-boat tone masks (source)

`decor_svg.py` writes `art/decor/decor_atlas.svg` + `.json` (Art Bible §6.6-6.8): leaf pinwheel
(two blade pairs + stick), six cairn pebbles, stepping stone, toadstool cap + stem, firefly
lantern (crook, glowing core, glass jar), four wind-chime tubes, the five gift items, the dew
drop, the basket's front rim (so gifts sit inside the env basket), the leaf boat and its candle,
and a dust mote. The JSON gives each part's region, size at depth 1, pivot, palettes.json
material, emission and rim flag, plus the placement layout `scripts/garden/decor_layer.gd`,
`basket_fill.gd` and `leaf_boats.gd` read (set scales, hook and slot positions).

Regenerate: `python3 -I -B art/decor/src/decor_svg.py && godot --headless --path . --import`.
Same tone-mask and import rules as `art/flora/src/README.md` (the kit is `art/flora/src/tonekit.py`).
