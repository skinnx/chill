// Shared material of every textured leaf in the sheets and modal cards (round 5, Art Bible §4.19):
// labels (glyph quads), duotone icons (one atlas) and the baked portrait / preview wells (one
// atlas page). One material for all of them, so they batch by texture only. It does two things:
//  * scroll content fades out at the scroll window's top and bottom edges (u_window / u_band in
//    canvas px; i_fade = 1), replacing the round-4 clip_children mask (a canvas group that cost
//    its own passes and stopped z-sorted children from batching);
//  * baked wells (rounded in the bake on a transparent page) are un-premultiplied here, so their
//    anti-aliased corners never darken.
// The fragment never re-samples TEXTURE: COLOR already holds texture x modulate (MSDF included).
shader_type canvas_item;
render_mode unshaded;

uniform vec4 u_window = vec4(-1e6, -1e6, 1e6, 1e6);
uniform vec2 u_band = vec2(24.0, 96.0);
// No instance uniforms (the global instance buffer is the world's, capped at 4096 slots on GLES3):
// UiBatch keeps one material per (fade, alpha, well) variant and gives each its own z slot.
uniform float u_fade = 0.0;
uniform float u_alpha = 1.0;
// Baked wells: the bake viewport stores premultiplied colour at the anti-aliased corners.
uniform float u_unpremultiply = 0.0;

varying vec2 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float a = COLOR.a * u_alpha;
	if (u_unpremultiply > 0.5) {
		COLOR.rgb /= max(COLOR.a, 1e-3);
	}
	if (u_fade > 0.5) {
		float top = smoothstep(u_window.y, u_window.y + u_band.x, v_world.y);
		float bottom = 1.0 - smoothstep(u_window.w - u_band.y, u_window.w, v_world.y);
		a *= top * bottom * step(u_window.x, v_world.x) * step(v_world.x, u_window.z);
	}
	COLOR.a = a;
}
