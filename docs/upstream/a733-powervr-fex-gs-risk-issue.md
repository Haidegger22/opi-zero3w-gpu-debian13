# [issue] Measured case of the documented GS risk: with `PVR_FAKE_GS=1` zink builds a *real* geometry-shader pipeline for GL_QUADS apps, and the blob aborts the process

## What this is

`gpu/vk-feature-strip/README.md` warns about exactly this and says it was never re-tested:

> **Known limits:** "With `PVR_FAKE_GS=1`, GL content that actually uses geometry shaders will crash the blob (rare for 2D/desktop GL; the fake is a query-only lie)."
> **Verified / not verified:** "Faking real GS pipelines crashing the blob is documented by this repo and was **not** re-tested (a driver hang on a headless board means a power cycle)."

We now have the measured case, and one detail in it changes the risk model: the trigger is **not** GL content that uses geometry shaders. Free software that never touches a geometry shader is enough — `glxgears`, `eglgears_x11`, `glxdemo`, `peglgears` are fixed-function GL 1.x/2.x quad demos. zink needs the geometry shader itself:

* with the faked bit, zink advertises `MESA_PRIM_QUADS` (it only does so when it sees `geometryShader`) and lowers quads with a self-generated GS — its NIR dump names it `filled quad gs`;
* the blob has no GS pipeline support, and its shader compiler calls `abort()` rather than returning an error.

So the sentence "Mesa only *queries* this bit; nothing turns on real GS pipelines" (README table, `PVR_FAKE_GS` row) does not hold on this stack: **Mesa turns on a real GS pipeline by itself**, without the app asking and without any GS shader in the app. Consequence: `PVR_FAKE_GS=1` is safe for the apps in the `glrun`/`d3drun` recipes, but it is not safe "for 2D/desktop GL" in general — the failing set is the classic quad-drawing demos.

## Detect it in one line (before spending a power cycle)

```sh
ZINK_DEBUG=nir <gl-app> 2>&1 | grep -c MESA_SHADER_GEOMETRY
```

* `0` → zink compiled no geometry shader for this program: it runs.
* `> 0` → zink compiled one (this stack: the generated `filled quad gs`): the program aborts with `SIGABRT` on this blob.

## Measured on this stack

Environment: Orange Pi Zero 3W (Allwinner A733, arm64), Debian 13 trixie, kernel `6.6.98-sun60iw2`, system Mesa `25.0.7-2+deb13u1`, PowerVR blob DDK `24.2@6603887` (`libVK_IMG.so`, `libufwriter.so`), layer from this repo with `PVR_FAKE_GS=1`.

| program | result | VP | **GS** | FP |
|---|---|---|---|---|
| `glxgears` (GL_QUADS, GLX window) | **SIGABRT** | 4 | **1** | 1 |
| `eglgears_x11` (GL_QUADS) | **SIGABRT** | 4 | **1** | 1 |
| `glxdemo` (GL_QUADS) | **SIGABRT** | 4 | **1** | 1 |
| `peglgears` (GL_QUADS) | **SIGABRT** | – | **1** | – |
| `es2gears_x11` | works | 1 | **0** | 3 |
| `es2tri` | works | – | **0** | – |
| `glxheads` | works | 3 | **0** | 1 |
| `glmark2` (GLX) | works | 6 | **0** | 18 |
| `vkgears` (Vulkan direct, no zink) | works | – | – | – |

Counts are `ZINK_DEBUG=nir` stage dumps. No exception to the rule in these runs: GS > 0 → abort, GS = 0 → fine. `ZINK_DEBUG=noopt` does not help (it is not an optimization-form problem).

## Trace

```sh
env -u LD_LIBRARY_PATH PVR_FAKE_GS=1 GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
    LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
    LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json DISPLAY=:0 \
    VK_LAYER_PATH=$HOME/.local/share/vulkan/implicit_layer.d VK_INSTANCE_LAYERS=VK_LAYER_PVR_strip \
    gdb -batch -ex run -ex "bt 25" --args glxgears -info
```

```
Thread 8 "glxgears:gdrv0" received signal SIGABRT, Aborted.
#0  0x0000007ff7b01ae0 in abort () from /lib/aarch64-linux-gnu/libc.so.6
#1..#10  ?? () from /usr/lib/libufwriter.so
#11 0x0000007fe88d34f8 in BILParseStream () from /usr/lib/libufwriter.so
#12..#14 ?? () from /lib/libVK_IMG.so
#15..#21 ?? () from /lib/aarch64-linux-gnu/libgallium-25.0.7-2+deb13u1.so
#22..#23 ?? () from /lib/aarch64-linux-gnu/libc.so.6
```

Notes for the "did the board survive" question the README raises: this abort is a plain user-space `SIGABRT` (exit 134) in the driver thread `gdrv0` — the kernel stayed up (`pvrsrvkm` clean, no power cycle needed), reproduced repeatedly on the same board. It is one level *below* the kernel-hang class of failure; it just kills the process.

## It does not go away if you drop the geometry shader

Measured, same stack, layer disabled for the process:

```
$ PVR_STRIP_DISABLE=1 glxgears
MESA: error: zink: Imagination proprietary driver w/o geometryShader is unsupported
glx: failed to create drisw screen
failed to load driver: zink
Error: couldn't get an RGB, Double-buffered visual
```

zink hard-requires `geometryShader` for `VK_DRIVER_ID_IMAGINATION_PROPRIETARY` and refuses to initialize without the lie. So there is no GS-free configuration on this stack: either the layer is on and zink can generate a GS that aborts the process, or it is off and there is no zink at all. That is different from `PVR_FAKE_R2`, where the README's mitigation ("it crashes when used, so keep it opt-in") actually works — here the crash needs no "use" of the faked feature by the app, only a GL_QUADS draw.

## Suggested README addition (ready to paste)

Replace/append in the layer README's **Known limits** section:

> **Measured crash case — the GS fake is not purely a query-time lie.** With `PVR_FAKE_GS=1`, zink *itself* creates real geometry-shader pipelines for legal GL content that contains no geometry shader at all. The common trigger is quads: zink advertises `MESA_PRIM_QUADS` only when it sees `geometryShader`, and lowers GL_QUADS with a self-generated GS (NIR dump name `filled quad gs`), so the fixed-function 1.x/2.x demos — `glxgears`, `eglgears_x11`, `glxdemo`, `peglgears` — abort with `SIGABRT` inside the vendor shader compiler (`BILParseStream()` in `libufwriter.so`, called from `libVK_IMG.so`, on the driver thread `gdrv0`). Check before shipping anything: `ZINK_DEBUG=nir <app> 2>&1 | grep -c MESA_SHADER_GEOMETRY` — non-zero means zink compiled a GS for that program and it will abort here. There is no GS-free fallback: `PVR_STRIP_DISABLE=1` does not make those apps run, it makes zink refuse to initialise (`zink: Imagination proprietary driver w/o geometryShader is unsupported`). The safe set stays what it was — apps for which zink never generates a GS (`glmark2`, `glmark2-es2`, `glxheads`, `es2gears_x11`). Reproduced on an Orange Pi Zero 3W (Debian 13 trixie, kernel `6.6.98-sun60iw2`, Mesa `25.0.7-2+deb13u1`, DDK `24.2@6603887`); the abort is a user-space `SIGABRT`, no kernel hang, no power cycle.

Also worth updating in the same README: the "Verified / not verified" note can drop the "**not** re-tested" caveat, and the `PVR_FAKE_GS=1` row's risk cell ("safe. Mesa only *queries* this bit; nothing turns on real GS pipelines") should read as "safe for apps that never draw quads and never use line stipple/smooth or points lowering — zink may still generate its own GS pipelines; verify with the one-liner above."

## Related upstream report

The zink-side of this is reported to Mesa separately (GL_QUADS lowering gated on the queried `geometryShader` bit; process abort instead of a graceful error). Not posted as of this writing.

## Sources

* Layer + recipe in this repo: `gpu/vk-feature-strip/` (layer source, its README), `gpu/zink-trixie.md` (zink recipe and switches), `docs/FINDINGS.md` (capability matrix)
* Mesa (bug-reporting docs and tracker): https://docs.mesa3d.org/bugs.html · https://gitlab.freedesktop.org/mesa/mesa/-/work_items
* Second published implementation of the same layer (not tested here): https://github.com/davidhfrankelcodes/pvr-a733-armbian
