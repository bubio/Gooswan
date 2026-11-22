// Framebuffer conversion, presentation, and CLI readback.
let front_vs = embed_shader("vert", """
    layout(location = 0) out vec2 v_uv;
    void main() {
        vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
        v_uv = vec2(p.x, 1.0 - p.y);
        gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
    }
    """);
let front_fs = embed_shader("frag", """
    layout(set = 2, binding = 0) uniform sampler2D tex;
    layout(location = 0) in vec2 v_uv;
    layout(location = 0) out vec4 o;
    void main() { o = texture(tex, v_uv); }
    """);

struct FrontVideo {
    texture:  gfx::Texture,
    nearest:  gfx::Sampler,
    linear:   gfx::Sampler,
    pipeline: gfx::Pipeline,
    width:    i64,
    height:   i64,
    viewport: float4                                  = float4 { 0.0, 0.0, 0.0, 0.0 },
    pixels:   u8[core::SCREEN_W * core::SCREEN_H * 4] = [0; core::SCREEN_W * core::SCREEN_H * 4],
}

fn front_video_size() -> i64, i64 {
    if settings.rotation == 0 { return core::SCREEN_W, core::SCREEN_H; }
    return core::SCREEN_H, core::SCREEN_W;
}

// Index in the rotated image, in pixels. The source is always SCREEN_W x SCREEN_H.
fn front_video_pixel_index(x: i64, y: i64, rotation: i64) -> i64 {
    return match rotation {
        1 => x * core::SCREEN_H + (core::SCREEN_H - 1 - y),
        2 => (core::SCREEN_W - 1 - x) * core::SCREEN_H + y,
        _ => y * core::SCREEN_W + x,
    };
}
fn front_video_open() -> FrontVideo {
    let w, h = front_video_size();
    return FrontVideo {
        texture:  gfx::texture2d(w, h),
        nearest:  gfx::sampler(gfx::NEAREST, gfx::CLAMP),
        linear:   gfx::sampler(gfx::LINEAR, gfx::CLAMP),
        pipeline: gfx::pipeline(front_vs, front_fs),
        width:    w, height: h,
    };
}

fn front_draw_video(video: FrontVideo&) {
    let w, h = front_video_size();
    if w != video.width || h != video.height {
        gfx::release(video.texture);
        video.texture = gfx::texture2d(w, h);
        video.width = w; video.height = h;
    }
    for y in core::SCREEN_H {
        for x in core::SCREEN_W {
            let color = if front_loaded { core::pixel(x, y) } else { 0 };
            let dst = front_video_pixel_index(x, y, settings.rotation) * 4;
            video.pixels[dst] = (((color >> 8) & 15) * 17) as! u8;
            video.pixels[dst + 1] = (((color >> 4) & 15) * 17) as! u8;
            video.pixels[dst + 2] = ((color & 15) * 17) as! u8;
            video.pixels[dst + 3] = 255;
        }
    }
    gfx::update_texture(video.texture, video.pixels[..]);

    let screen = gfx::screen_size();
    let density = max(hostwindow_scale(), 1.0);
    let top = if front_check { 0.0 } else { FRONT_MENU_HEIGHT * density };
    let bottom = if front_check { 0.0 } else { FRONT_STATUS_HEIGHT * density };
    let available_w = screen.x as f32;
    let available_h = max(screen.y - top - bottom, 1.0);
    let zoom = min(available_w / w, available_h / h);
    let draw_w = w * zoom;
    let draw_h = h * zoom;
    let left = (available_w - draw_w) / 2.0;
    let y = top + (available_h - draw_h) / 2.0;
    video.viewport = float4 { left, y, draw_w, draw_h };

    gfx::begin_screen(float4 { 0.0, 0.0, 0.0, 1.0 });
    gfx::viewport(left, y, draw_w, draw_h);
    gfx::bind(video.pipeline);
    gfx::bind_texture(gfx::FRAGMENT, 0, video.texture, if settings.linear && !front_check { video.linear } else { video.nearest });
    gfx::draw(3);
    gfx::end_pass();
}

fn front_video_mismatches(video: const FrontVideo&) -> i64 {
    gfx::frame();
    let pixels = gfx::read_pixels(gfx::screen());
    let screen = gfx::screen_size();
    let viewport = video.viewport;
    let w = video.width; let h = video.height;
    if pixels.len != screen.x * screen.y * 4 || viewport.z < w || viewport.w < h { return -1; }
    var bad: i64 = 0;
    for y in h {
        for x in w {
            let xx = (viewport.x + (x + 0.5) * viewport.z / w) as! i64;
            let yy = (viewport.y + (y + 0.5) * viewport.w / h) as! i64;
            let src = (yy * screen.x + xx) * 4;
            let dst = (y * w + x) * 4;
            if pixels[src..src + 3] != video.pixels[dst..dst + 3] { bad += 1; }
        }
    }
    return bad;
}
