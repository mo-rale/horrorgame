shader_type spatial;
render_mode unshaded, fog_disabled;

uniform sampler2D screen_texture : hint_screen_texture;
uniform float pixel_size : hint_range(1.0, 20.0) = 4.0;

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    vec2 screen_size = vec2(textureSize(screen_texture, 0));
    vec2 pixel_count = screen_size / (pixel_size * 2.);
    vec2 pixelated_uv = floor(SCREEN_UV * pixel_count) / pixel_count;
    vec4 color = texture(screen_texture, pixelated_uv);

    ALBEDO = color.rgb;
    ALPHA = color.a;
}