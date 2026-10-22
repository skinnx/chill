# Tea atlas (Active F2 Tea & Treats)

`src/tea_svg.py` writes `tea_atlas.svg` + `tea_atlas.json` (run `python3 -I art/tea/src/tea_svg.py`
from the repo root). One felt-sticker atlas for the tea nook on the stump (`scripts/garden/tea_nook.gd`,
lit by `shaders/props/tea_nook.gdshader`) and the Tea sheet (`scripts/ui/tea_pot.gd`, `tea_icon.gd`),
so each draws as one batch.

- Tintable pieces (teapot, lid, cups, tea, petals, cloth, treat) are authored in neutral felt grey
  with the cocoa outline (`dock_icon.outline`); the views multiply them by a flower colour
  (`palettes.json flora.flowers.fl_*.petal[0]`) or a teaware colour.
- `teaware` in the JSON is a placeholder colour pair per teaware id (tea.json) until the Art
  Director's set (GDD §14.11); `glow` marks the night pieces.
- `white` / `dot` are plain texels: rings, swirls and the pour stream are chains of them, so they
  batch with the pieces.
