# Flora tone masks (source)

`flora_svg.py` writes the flower-bed stamp atlas (Art Bible §6.1-6.3, §4.10):

- `art/flora/flora_atlas.svg` + `.json`: petals, heads, buds, leaves, stems, foliage clumps, soil,
  the bed shadow, glints, sparkles, the tutorial seed and the butterfly wing, packed into one
  texture at 2x (`scale`), read by `scripts/flora/flora_builder.gd` and drawn with
  `shaders/flora/flora_bed.gdshader` (one mesh per bed).
- The JSON also carries the per-form grammar (`forms`: stem length/width, lean, leaves, rosette,
  head, bud), the growth rules (`growth`) and the bed-wide size multipliers (`bed_scale`).

`tonekit.py` is the small authoring kit shared with `art/decor/src/decor_svg.py`.

Regenerate after editing (deterministic, seeded):

```
python3 -I -B art/flora/src/flora_svg.py
python3 -I -B art/decor/src/decor_svg.py
godot --headless --path . --import
```

Tone-mask rules: pure R = lit, G = shade, B = detail, black = colour-line tone, alpha = coverage;
gradients only between pure channels; filled, rounded shapes; no `<text>`; `feGaussianBlur` only;
no dark ink outlines (the felt look comes from the shader's fibre fringe). Import settings:
lossless, mipmaps on (the shader's rim and fringe read a blurred mip), fix alpha border,
`svg/scale = 1.0`. This folder has a `.gdignore`, so Godot never imports or exports the generator.
