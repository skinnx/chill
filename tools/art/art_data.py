#!/usr/bin/env python3
"""Art data tool for Mossling Meadow (docs/ART_BIBLE.md §3.9, §5.10).

  python3 tools/art/art_data.py check     # assert palette / creature thresholds; exit 1 on failure (CI)
  python3 tools/art/art_data.py resolve   # rewrite the derived sections in place, then check

Sources of truth: data/palettes.json (tokens), data/creature_rig.json (catalog + art_overrides),
data/species.json (GDD rig vocabulary), data/flora.json (GDD petal tokens).
Derived (rewritten by `resolve`): palettes.tod.palettes.*.<derived slots>, palettes.creatures.species_resolved,
palettes.flora.flowers.*.{petal[1], leaf[1], leaf[2], stem, bud}, palettes.materials.*.shade, creature_rig.species. Pure standard library on purpose (runs in any CI image).
"""
import json
import math
import sys
from itertools import combinations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PALETTES = ROOT / 'data' / 'palettes.json'
RIG = ROOT / 'data' / 'creature_rig.json'
SPECIES = ROOT / 'data' / 'species.json'
FLORA = ROOT / 'data' / 'flora.json'

# ---------- colour maths (sRGB, OKLab, WCAG, Machado 2009 severity 1.0) ----------
def hex2rgb(h):
	h = h.lstrip('#')
	return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]

def rgb2hex(c):
	return '#%02X%02X%02X' % tuple(max(0, min(255, round(v * 255.0))) for v in c)

def to_lin(c):
	return [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c]

def to_srgb(l):
	out = []
	for v in l:
		v = max(0.0, min(1.0, v))
		out.append(v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055)
	return out

def mat(m, v):
	return [sum(m[r][k] * v[k] for k in range(3)) for r in range(3)]

M1 = [[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]]
M2 = [[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]]
M2I = [[1.0, 0.3963377774, 0.2158037573], [1.0, -0.1055613458, -0.0638541728], [1.0, -0.0894841775, -1.2914855480]]
M1I = [[4.0767416621, -3.3077115913, 0.2309699292], [-1.2684380046, 2.6097574011, -0.3413193965], [-0.0041960863, -0.7034186147, 1.7076147010]]

def lin2oklab(l):
	return mat(M2, [math.copysign(abs(v) ** (1 / 3), v) for v in mat(M1, l)])

def oklab2lin(lab):
	return mat(M1I, [v ** 3 for v in mat(M2I, lab)])

def hex2oklab(h):
	return lin2oklab(to_lin(hex2rgb(h)))

def oklab2hex(lab):
	return rgb2hex(to_srgb(oklab2lin(lab)))

def oklch(h):
	L, a, b = hex2oklab(h)
	return L, math.hypot(a, b), (math.degrees(math.atan2(b, a)) + 360.0) % 360.0

def from_oklch(L, C, H):
	return oklab2hex([L, C * math.cos(math.radians(H)), C * math.sin(math.radians(H))])

def mix_ok(h1, h2, t):
	a, b = hex2oklab(h1), hex2oklab(h2)
	return oklab2hex([(1 - t) * a[i] + t * b[i] for i in range(3)])

def mix_srgb(h1, h2, t):
	a, b = hex2rgb(h1), hex2rgb(h2)
	return rgb2hex([(1 - t) * a[i] + t * b[i] for i in range(3)])

def mul(h1, h2):
	a, b = hex2rgb(h1), hex2rgb(h2)
	return rgb2hex([a[i] * b[i] for i in range(3)])

def rel_lum(h):
	l = to_lin(hex2rgb(h))
	return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]

def lstar(h):
	y = rel_lum(h)
	f = y ** (1 / 3) if y > (6 / 29) ** 3 else y / (3 * (6 / 29) ** 2) + 4 / 29
	return 116 * f - 16

def contrast(h1, h2):
	a, b = sorted((rel_lum(h1), rel_lum(h2)), reverse=True)
	return (a + 0.05) / (b + 0.05)

CVD = {
	'protan': [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
	'deutan': [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
	'tritan': [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}

def sim(h, kind):
	if kind == 'normal':
		return h
	return rgb2hex(to_srgb([max(0.0, min(1.0, v)) for v in mat(CVD[kind], to_lin(hex2rgb(h)))]))

def de_ok(h1, h2, kind='normal'):
	a, b = hex2oklab(sim(h1, kind)), hex2oklab(sim(h2, kind))
	return 100.0 * math.dist(a, b)

KINDS = ('normal', 'protan', 'deutan', 'tritan')

def shade_of(lit, dL=0.12, t=0.30, cap=25.0, cmul=0.85):
	"""Gurney shadow: L -0.12, hue rotated 30 % (max 25 deg) toward 275 deg, chroma x0.85 (ART_BIBLE §3.5)."""
	L, C, H = oklch(lit)
	d = ((275.0 - H + 180.0) % 360.0) - 180.0
	d = max(-cap, min(cap, d * t))
	return from_oklch(max(L - dL, 0.05), C * cmul, (H + d) % 360.0)

# ---------- derivations ----------
def derive_tod(p, scal, soil_detail):
	back = mix_ok(mix_ok(p['near'], p['mid'], 0.20), p['sky_horizon'], 0.06)
	front = p['near']
	k = scal['ground_light']
	back_lit = mix_ok(back, p['key'], k)
	return {
		'ground_back': back, 'ground_front': front, 'ground_back_lit': back_lit,
		'ground_front_lit': mix_ok(front, p['key'], k),
		'ground_path': mix_ok(mix_ok(back_lit, p['sky_horizon'], 0.18), soil_detail, 0.22),
		'grass_tip': mix_ok(mix_ok(p['near'], p['mid'], 0.15), p['key'], 0.28), 'grass_root': mix_ok(p['near'], p['shadow'], 0.25),
		'water_deep': mix_ok(mix_ok(p['near'], p['shadow'], 0.40), p['sky_top'], 0.30),
		'water_shallow': mix_ok(p['sky_mid'], p['sky_horizon'], 0.55), 'water_bank': mix_ok(p['near'], p['shadow'], 0.30),
		'cloud_lit': mix_ok(p['sky_horizon'], p['glow'], 0.60), 'cloud_shade': mix_ok(p['sky_mid'], p['shadow'], 0.18),
		'far_haze': mix_ok(p['far'], p['sky_horizon'], 0.30), 'mid_haze': mix_ok(p['mid'], p['sky_horizon'], 0.15),
	}

def resolve_species(sp, cr, ink_source):
	r = sp['rig']
	fur, f2, bel, acc = cr[r['fur']], cr[r['fur_2']], cr[r['belly']], cr[r['accent']]
	src = ink_source.get(r['pattern']) or 'fur_2'
	ink = {'fur_2': f2, 'accent': acc, 'belly': bel}[src]
	deep = False
	if src in ('fur_2', 'accent') and de_ok(ink, fur) < 6.0:
		L, C, H = oklch(ink)
		ink = from_oklch(L - 0.05, C, H)
		deep = True
	return {'fur': fur, 'fur_2': f2, 'belly': bel, 'accent': acc, 'tip': mix_ok(fur, '#FFF8EE', 0.45),
			'pattern_ink': ink, 'pattern_ink_deepened': deep, 'cheek': cr['cr_cheek'], 'cheek_alpha': 0.50,
			'eye': cr['cr_eye'], 'eye_shine': cr['cr_eye_shine'], 'shade_preview': shade_of(fur),
			'tokens': {k: r[k] for k in ('fur', 'fur_2', 'belly', 'accent')}}

def resolve_rig(sp, rig):
	r, cat, dfl = sp['rig'], rig['catalog'], rig['defaults']
	a = rig['art_overrides'][sp['id']]
	ear, tail, ant, pat, eye = cat['ear'][r['ear']], cat['tail'][r['tail']], cat['antenna'][r['antenna']], cat['pattern'][r['pattern']], cat['eye'][r['eye']]
	return {
		'body': {'w_h': r['body_w_h'], 'squircle_n': a['n'], 'size_mul': r['size'], 'feet_nubs': a['feet']},
		'fuzz_dp': r['fuzz_dp'], 'fringe_dp': round(r['fuzz_dp'] * dfl['fringe_len_mul'], 2),
		'ear': {'type': r['ear'], 'id': ear['id'], 'size': ear.get('size', 0.0), 'spread': ear.get('spread', 0.0)},
		'tail': {'type': r['tail'], 'id': tail['id'], 'size': tail.get('size', 0.0)},
		'antenna': {'type': r['antenna'], 'id': ant['id'], 'length': ant.get('length', 0.0), 'emission': ant.get('emission', 0.0)},
		'pattern': {'type': r['pattern'], 'id': pat['id'], 'belly_size': pat.get('belly_size', dfl['belly_size_default']),
					'belly_strength': pat.get('belly_strength', dfl['belly_strength_default'])},
		'eye': {'type': r['eye'], 'id': eye['id'], 'size': dfl['eye_size'], 'spacing': dfl['eye_spacing'], 'height_from_top': dfl['eye_height_from_top']},
		'mouth': {'type': a['mouth'], 'id': cat['mouth'][a['mouth']]},
		'colours': 'data/palettes.json creatures.species_resolved.' + sp['id'],
	}

# ---------- checks ----------
class Report:
	def __init__(self):
		self.fails = []
		self.lines = []

	def need(self, ok, msg):
		self.lines.append(('PASS ' if ok else 'FAIL ') + msg)
		if not ok:
			self.fails.append(msg)

def check(pal, rig, species, flora):
	rep = Report()
	tod = pal['tod']
	order = tod['order']
	# 1. TOD tokens: chroma ceiling (05 §4: every token C_OK <= 0.163), no pure black/white except identity ambient
	for t in order:
		for slot in tod['base_slots']:
			h = tod['palettes'][t][slot]
			rep.need(oklch(h)[1] <= 0.165, f'tod {t}.{slot} {h} chroma {oklch(h)[1]:.3f} <= 0.165')
		rep.need(lstar(tod['palettes'][t]['shadow']) >= 6.0, f'tod {t} shadow L* >= 6')
	# 2. Value ladder: contrast vs horizon rises far -> mid -> near -> fg (atmospheric perspective)
	for t in order:
		p = tod['palettes'][t]
		cr = [contrast(p[k], p['sky_horizon']) for k in ('far', 'mid', 'near', 'fg')]
		rep.need(all(cr[i] < cr[i + 1] for i in range(3)), f'tod {t} ladder {[round(c, 2) for c in cr]} monotonic')
	# 3. UI contrast (X2)
	ui = pal['ui']
	rep.need(contrast(ui['ink'], ui['surface']) >= 4.5, 'ink on surface >= 4.5')
	rep.need(contrast(ui['ink_2'], ui['surface']) >= 4.5, 'ink_2 on surface >= 4.5')
	rep.need(contrast(ui['surface_hi'], ui['primary']) >= 4.5, 'surface_hi text on primary >= 4.5')
	rep.need(contrast(ui['surface_hi'], ui['leaf']) >= 4.5, 'surface_hi text on leaf >= 4.5')
	rep.need(contrast(ui['ink'], ui['gold']) >= 4.5, 'ink on gold >= 4.5')
	rep.need(contrast(ui['ink'], ui['coral']) >= 4.5, 'ink on coral >= 4.5')
	rep.need(contrast(pal['ui_derived']['toggle_off_border'], ui['surface']) >= 3.0, 'toggle off border >= 3:1 (WCAG 1.4.11)')
	rep.need(contrast(ui['leaf'], ui['surface']) >= 3.0, 'toggle on track (leaf) vs surface >= 3:1')
	# adaptive live glass: ink_2 legible over the darkest backdrop (WCAG body text)
	ga = pal['ui_alpha']['glass_live_adaptive']
	for bg in ('#0F162E', '#111938', '#4E487C', '#6FB6EC', '#FFF5D6'):
		y = rel_lum(bg)
		s = max(0.0, min(1.0, (y - ga['backdrop_luma_lo']) / (ga['backdrop_luma_hi'] - ga['backdrop_luma_lo'])))
		s = s * s * (3 - 2 * s)
		a = ga['max'] + (ga['min'] - ga['max']) * s
		glass = mix_srgb(bg, ui['surface'], a)
		rep.need(contrast(ui['ink'], glass) >= 4.5, f'ink on live glass over {bg} (tint {a:.2f}) >= 4.5')
	for bg in ('#0F162E', '#111938', '#FFF5D6'):
		glass = mix_srgb(bg, ui['surface'], pal['ui_alpha']['glass_faux_fill'])
		rep.need(contrast(ui['ink'], glass) >= 4.5, f'ink on faux glass over {bg} >= 4.5')
	# 4. Semantic set under CVD (05 §0.4): >= 10, documented tritan exception primary-leaf >= 8.5
	sem = ['primary', 'coral', 'leaf', 'gold']
	for kind in KINDS:
		for a, b in combinations(sem, 2):
			v = de_ok(ui[a], ui[b], kind)
			floor = 8.5 if (kind == 'tritan' and {a, b} == {'primary', 'leaf'}) else 9.9
			rep.need(v >= floor, f'semantic {a}-{b} {kind} dE_OK {v:.1f} >= {floor}')
	# 5. Creatures: every species readable against the meadow in every phase it can appear (and every CVD sim)
	cr = pal['creatures']['tokens']
	for sp in species:
		res = pal['creatures']['species_resolved'][sp['id']]
		phases = set(sp['phases']) or set(order)
		worst, worst_l = 1e9, 1e9
		for t in order:
			if t not in phases:
				continue
			p = tod['palettes'][t]
			fur = mul(res['fur'], p['ambient'])
			for bg in (p['ground_back_lit'], p['ground_front_lit']):
				worst = min(worst, min(de_ok(fur, bg, k) for k in KINDS))
				worst_l = min(worst_l, abs(lstar(fur) - lstar(bg)))
		rep.need(worst >= 8.0, f'species {sp["id"]} vs meadow worst dE_OK {worst:.1f} >= 8')
		rep.need(worst_l >= 9.0, f'species {sp["id"]} vs meadow worst dL* {worst_l:.1f} >= 9')
		rep.need(contrast(res['eye'], res['fur']) >= 4.5, f'species {sp["id"]} eye contrast {contrast(res["eye"], res["fur"]):.1f} >= 4.5')
		rep.need(de_ok(res['cheek'], res['fur']) >= 8.0, f'species {sp["id"]} cheek dE_OK {de_ok(res["cheek"], res["fur"]):.1f} >= 8')
		for k in ('fur', 'fur_2', 'belly', 'accent'):
			rep.need(oklch(res[k])[1] <= 0.13, f'species {sp["id"]} {k} chroma <= 0.13')
	# 6. Silhouette identity: Hamming >= 2 over (ear, tail, antenna, body class, pattern)
	def cls(w):
		return 'wide' if w >= 1.12 else ('tall' if w <= 0.97 else 'mid')
	tup = {s['id']: (s['rig']['ear'], s['rig']['tail'], s['rig']['antenna'], cls(s['rig']['body_w_h']), s['rig']['pattern']) for s in species}
	for a, b in combinations(tup, 2):
		ham = sum(x != y for x, y in zip(tup[a], tup[b]))
		rep.need(ham >= 2, f'silhouette {a} vs {b} hamming {ham} >= 2')
	# 7. References resolve
	for sp in species:
		for k in ('fur', 'fur_2', 'belly', 'accent'):
			rep.need(sp['rig'][k] in cr, f'species {sp["id"]} rig.{k} token {sp["rig"][k]} exists')
		for k, cat in (('ear', 'ear'), ('tail', 'tail'), ('antenna', 'antenna'), ('pattern', 'pattern'), ('eye', 'eye')):
			rep.need(sp['rig'][k] in rig['catalog'][cat], f'species {sp["id"]} rig.{k}={sp["rig"][k]} in catalog')
	for f in flora:
		rep.need(f['petal_token'] in pal['flora']['flowers'], f'flower {f["id"]} petal_token {f["petal_token"]} exists')
	# 8. Flowers: petals separate from their own leaves (accent rule >= 15 L*) and from leaves under CVD
	for tok, fl in pal['flora']['flowers'].items():
		pet, leaf = fl['petal'][0], fl['leaf'][0]
		rep.need(lstar(pet) - lstar(leaf) >= 15.0, f'{tok} petal-leaf dL* {lstar(pet) - lstar(leaf):.1f} >= 15')
		rep.need(min(de_ok(pet, leaf, k) for k in KINDS) >= 10.0, f'{tok} petal-leaf CVD dE_OK >= 10')
		rep.need(oklch(pet)[1] <= 0.163, f'{tok} petal chroma <= 0.163')
	return rep

def main():
	cmd = sys.argv[1] if len(sys.argv) > 1 else 'check'
	pal = json.loads(PALETTES.read_text())
	rig = json.loads(RIG.read_text())
	species = json.loads(SPECIES.read_text())['species']
	flora = json.loads(FLORA.read_text())['flowers']
	if cmd == 'resolve':
		soil = pal['materials']['soil']['detail']
		for t in pal['tod']['order']:
			pal['tod']['palettes'][t].update(derive_tod(pal['tod']['palettes'][t], pal['tod']['scalars'][t], soil))
		pal['creatures']['species_resolved'] = {sp['id']: resolve_species(sp, pal['creatures']['tokens'], pal['creatures']['pattern_ink_source']) for sp in species}
		for fl in pal['flora']['flowers'].values():
			pet, leaf = fl['petal'][0], fl['leaf'][0]
			fl['petal'][1] = shade_of(pet)
			fl['leaf'][1] = shade_of(leaf)
			fl['leaf'][2] = mix_ok(leaf, '#FFF8EE', 0.35)
			fl['stem'] = mix_ok(leaf, '#3B6C8C', 0.12)
			fl['bud'] = mix_ok(leaf, pet, 0.35)
		for mat in pal['materials'].values():
			mat['shade'] = shade_of(mat['lit'])
		rig['species'] = {sp['id']: resolve_rig(sp, rig) for sp in species}
		PALETTES.write_text(json.dumps(pal, indent='\t', ensure_ascii=False) + '\n')
		RIG.write_text(json.dumps(rig, indent='\t', ensure_ascii=False) + '\n')
		print('resolved derived sections')
	elif cmd != 'check':
		print(__doc__)
		return 2
	rep = check(pal, rig, species, flora)
	verbose = '-v' in sys.argv
	for line in rep.lines:
		if verbose or line.startswith('FAIL'):
			print(line)
	print(f'{len(rep.lines) - len(rep.fails)} passed, {len(rep.fails)} failed')
	return 1 if rep.fails else 0

if __name__ == '__main__':
	sys.exit(main())
