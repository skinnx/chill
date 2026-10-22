# Prop and foreground tone masks (source)

`props_svg.py` writes the two atlases the world draws from (Art Bible §4.9, §4.16, §6.4-6.5):

- `art/props/props_atlas.svg` + `.json`: every prop and art-dressing piece (willow crown, curtains,
  trunk and chime branch, mailbox, stump, basket, sun stone, spring rock, glow mushrooms, reeds,
  fern, clover, moss mound, moon rock, pebbles) packed into one texture, read by
  `scripts/world/props_layer.gd` with one shared `shaders/props/prop_tone.gdshader` material.
- `art/props/fg_atlas.svg` + `.json`: the L5 foreground frame (reeds, clover, bough), read by
  `scripts/world/foreground_frame.gd` with `shaders/world/fg_frame.gdshader`.

Regenerate after editing a part (deterministic, seeded):

```
python3 -I art/props/src/props_svg.py
godot --headless --path . --import
```

Tone-mask rules: pure R = lit, G = shade, B = detail, black = colour-line tone, alpha = coverage;
gradients only between pure channels; filled, rounded shapes; no `<text>`; `feGaussianBlur` only.
Touchable props carry a 6 px colour line. Each part's layout entry gives its spots.json prop (or an
absolute art-dressing position), y-sort origin, material, contact shadow, sway and flags; see the
module docstring. Import settings: lossless, mipmaps on, fix alpha border, `svg/scale = 1.0`.
This folder has a `.gdignore`, so Godot never imports or exports the generator.
