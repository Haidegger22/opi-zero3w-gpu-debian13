# [Mesa work item] zink: GL_QUADS lowering trusts the queried `geometryShader` bit and builds a real GS pipeline; a driver that advertises GS but cannot execute it aborts the process (Imagination proprietary, BXM-4-64)

## Describe the bug

Reproduced on: **Orange Pi Zero 3W** (Allwinner A733 `sun60iw2`, arm64), Debian 13 trixie, kernel `6.6.98-sun60iw2` (vendor BSP, out-of-tree `pvrsrvkm`), system Mesa **25.0.7** (`zink` gallium driver) on the closed PowerVR Vulkan driver.

A plain fixed-function GL 2.1 program that draws `GL_QUADS` (`glxgears`, `eglgears_x11`, `glxdemo`, `peglgears`) leaves zink through a **self-generated geometry shader**, and on this driver that kills the process: the vendor shader compiler calls `abort()` instead of failing pipeline creation.

### What zink does, from the 25.0 sources

* `zink_screen.c:793-795` — `MESA_PRIM_QUADS` is advertised in `caps->supported_prim_modes` when `have_triangle_fans && geometryShader`; `have_triangle_fans` defaults to `true` (`zink_screen.c:3509`). So **quad support is gated on the queried geometry-shader feature bit**.
* `zink_program.c:2516` — the whole generated-GS lowering returns early if `!screen->info.feats.features.geometryShader`.
* `zink_program.c:2564-2591` — for `gfx_prim_mode == MESA_PRIM_QUADS` zink generates `zink_create_quads_emulation_gs()` (`zink_compiler.c:1070-1084`, shader name `"filled quad gs"`, `LINES_ADJACENCY` in / `TRIANGLE_STRIP` out, 4 vertices in / 6 out) and binds it as a real GS stage. The app never asked for a geometry shader; zink needs it because Vulkan has no quad topology.

So: a legal, GS-free GL 2.1 draw becomes a **real GS pipeline** on the basis of one queried feature bit. On a driver that advertises the bit but cannot execute GS pipelines, that is process death.

### Why the driver in this report advertises a GS it cannot run (not a Mesa bug, but the trigger)

The device is a closed PowerVR blob with `geometryShader = VK_FALSE`. To use zink at all on it, a third-party Vulkan layer is installed (`VK_LAYER_PVR_strip` from `github.com/ayiejosh/a733-powervr-fex`, `gpu/vk-feature-strip/`, enabled with `PVR_FAKE_GS=1`). The layer reports `geometryShader = VK_TRUE` from `vkGetPhysicalDeviceFeatures` and removes the bit from `VkDeviceCreateInfo` before forwarding to the driver. Order of operations, so no Vulkan API misuse is being reported here:

1. zink queries features, sees `geometryShader = VK_TRUE`;
2. zink enables it in its own `VkDeviceCreateInfo` (the Khronos validation layer, enabled correctly, sees a consistent request and reports **no** Vulkan API error before the abort);
3. the layer strips the bit, the blob accepts the device;
4. later zink creates the generated quad GS pipeline, the blob's shader compiler aborts.

Removing the lie is **not** a workaround for us: with `PVR_STRIP_DISABLE=1` (honest `geometryShader = VK_FALSE`) zink refuses to initialize — `zink_screen.c:3457-3461` (25.0) hard-fails screen creation for `VK_DRIVER_ID_IMAGINATION_PROPRIETARY` when the feature is missing:

```
MESA: error: zink: Imagination proprietary driver w/o geometryShader is unsupported
glx: failed to create drisw screen
failed to load driver: zink
Error: couldn't get an RGB, Double-buffered visual
```

That check exists because zink sets the `no_linesmooth` workaround for this driver ID and asserts the feature (`zink_screen.c:2903-2907`). Net effect: on this driver there is **no** zink configuration in which a GL_QUADS draw does not become a GS pipeline — either zink does not start, or it starts and the blob aborts.

## Environment

| | |
|---|---|
| Mesa version / build | `25.0.7-2+deb13u1` (Debian trixie distro build, **no debug symbols**; `/lib/aarch64-linux-gnu/libgallium-25.0.7-2+deb13u1.so`) |
| Architecture | `aarch64` (arm64) |
| Vulkan driver / ICD | PowerVR **B-Series BXM-4-64 MC1**, `driverID = 7` (`VK_DRIVER_ID_IMAGINATION_PROPRIETARY`), Vulkan **1.3.277**, DDK **24.2@6603887**, ICD `/usr/share/vulkan/icd.d/img_icd.json`, `/lib/libVK_IMG.so`, `/usr/lib/libufwriter.so` |
| Device features as actually reported by the blob (layer inert) | `geometryShader = VK_FALSE`, `fillModeNonSolid = VK_FALSE`, `wideLines = VK_TRUE` (checked with `PVR_STRIP_DISABLE=1 vulkaninfo`) |
| Board / OS / kernel | Orange Pi Zero 3W, Allwinner A733 (`sun60iw2`), Debian 13 trixie, `6.6.98-sun60iw2` |
| Working zink renderer string | `zink Vulkan 1.3(PowerVR B-Series BXM-4-64 MC1 (IMAGINATION_PROPRIETARY))`, GL 2.1 |

Note on `LD_LIBRARY_PATH`: the board also has a vendor Mesa 24.0.1 in `/usr/local` with ldconfig priority, so the zink path must run with a **scoped** `LD_LIBRARY_PATH` selecting the system Mesa 25.0.7 (`env -u LD_LIBRARY_PATH … LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu`).

## Steps to reproduce

Sanity check that the stack itself works (off-screen / non-quad apps render fine):

```sh
env -u LD_LIBRARY_PATH \
    PVR_FAKE_GS=1 \
    GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
    LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
    LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json \
    DISPLAY=:0 glxinfo -B
# -> OpenGL renderer string: zink Vulkan 1.3(PowerVR B-Series BXM-4-64 MC1 (IMAGINATION_PROPRIETARY))
```

The crash (GL_QUADS app, with the layer as an explicit layer — `VK_LAYER_PATH` alone only makes the manifest discoverable, an explicit layer is never auto-enabled):

```sh
env -u LD_LIBRARY_PATH \
    PVR_FAKE_GS=1 \
    GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
    LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
    LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json \
    VK_LAYER_PATH=$HOME/.local/share/vulkan/implicit_layer.d \
    VK_INSTANCE_LAYERS=VK_LAYER_PVR_strip \
    DISPLAY=:0 gdb -batch -ex run -ex "bt 25" --args glxgears -info
```

Same result without gdb (`SIGABRT`, exit 134, within the first frames after the window is mapped; reproduced repeatedly on this board). The layer variant used is published as `gpu/vk-feature-strip/` in `github.com/ayiejosh/a733-powervr-fex` (branch `trixie`); a second published implementation exists at `github.com/davidhfrankelcodes/pvr-a733-armbian` (not tested here).

## Expected vs. actual behaviour

* **Expected:** zink either renders `GL_QUADS` without a geometry shader (topology conversion), or reports a clean error — nothing in this program requires GS.
* **Actual:** `SIGABRT` (exit 134) with the abort inside the vendor shader compiler, on Mesa's driver thread `gdrv0`. No Mesa-level error is printed; the last Mesa output is the unrelated `fillModeNonSolid` warning (`WARNING: Some incorrect rendering might occur because the selected Vulkan device (PowerVR B-Series BXM-4-64 MC1) doesn't support base Zink requirements: feats.features.fillModeNonSolid`).

## Shader stage distribution per program (`ZINK_DEBUG=nir` dumps, everything through zink)

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

Rule with no exceptions in these runs: every program for which zink compiles a GS dies; every program with no GS works.

## The generated GS, as dumped

```
NIR shader:
---8<---
shader: MESA_SHADER_GEOMETRY
name: filled quad gs
internal: true
next_stage: MESA_SHADER_VERTEX
inputs_read: 0-1,21
output_primitive: TRIANGLE_STRIP
input_primitive: LINES_ADJACENCY
vertices_out: 6
invocations: 1
vertices_in: 4
uses_end_primitive: true
active_stream_mask: 0x01
```

`name: filled quad gs` and the `LINES_ADJACENCY`/`TRIANGLE_STRIP`/4-in/6-out combination are set by `zink_create_quads_emulation_gs()` (`zink_compiler.c:1070-1084`, 25.0) — i.e. this is the GL_QUADS emulation, entered from `zink_program.c:2564-2591`. TODO: the exact NIR pass/entry in the *installed build* was identified from the dump's `name:` field plus the 25.0 tree, not from a build with symbols; the distro library is stripped.

## Backtrace

```
[New Thread 0x7fcffff180 (LWP 940733)]
WARNING: Some incorrect rendering might occur because the selected Vulkan device (PowerVR B-Series BXM-4-64 MC1) doesn't support base Zink requirements: feats.features.fillModeNonSolid

Thread 8 "glxgears:gdrv0" received signal SIGABRT, Aborted.
[Switching to Thread 0x7fcffff180 (LWP 940733)]
0x0000007ff7b01ae0 in abort () from /lib/aarch64-linux-gnu/libc.so.6
#0  0x0000007ff7b01ae0 in abort () from /lib/aarch64-linux-gnu/libc.so.6
#1  0x0000007fe8a34030 in ?? () from /usr/lib/libufwriter.so
#2  0x0000007fe88be29c in ?? () from /usr/lib/libufwriter.so
#3  0x0000007fe88be974 in ?? () from /usr/lib/libufwriter.so
#4  0x0000007fe88be860 in ?? () from /usr/lib/libufwriter.so
#5  0x0000007fe88bf0d0 in ?? () from /usr/lib/libufwriter.so
#6  0x0000007fe88bf224 in ?? () from /usr/lib/libufwriter.so
#7  0x0000007fe88c1ba0 in ?? () from /usr/lib/libufwriter.so
#8  0x0000007fe88d0c74 in ?? () from /usr/lib/libufwriter.so
#9  0x0000007fe8a277c4 in ?? () from /usr/lib/libufwriter.so
#10 0x0000007fe88d3424 in ?? () from /usr/lib/libufwriter.so
#11 0x0000007fe88d34f8 in BILParseStream () from /usr/lib/libufwriter.so
#12 0x0000007feb85f774 in ?? () from /lib/libVK_IMG.so
#13 0x0000007feb8644a8 in ?? () from /lib/libVK_IMG.so
#14 0x0000007feb86a1f0 in ?? () from /lib/libVK_IMG.so
#15 0x0000007ff6210f18 in ?? () from /lib/aarch64-linux-gnu/libgallium-25.0.7-2+deb13u1.so
#16 0x0000007ff61d463c in ?? () from /lib/aarch64-linux-gnu/libgallium-25.0.7-2+deb13u1.so
#17 0x0000007ff61d488c in ?? () from /lib/aarch64-linux-gnu/libgallium-25.0.7-2+deb13u1.so
#18 0x0000007ff61d9ce8 in ?? () from /lib/aarch64-linux-gnu/libgallium-25.0.7-2+deb13u1.so
#19 0x0000007ff5bc0f4c in ?? () from /lib/aarch64-linux-gnu/libgallium-25.0.7-2+deb13u1.so
#20 0x0000007ff59e95c8 in ?? () from /lib/aarch64-linux-gnu/libgallium-25.0.7-2+deb13u1.so
#21 0x0000007ff5a0ea40 in ?? () from /lib/aarch64-linux-gnu/libgallium-25.0.7-2+deb13u1.so
#22 0x0000007ff7b65f38 in ?? () from /lib/aarch64-linux-gnu/libc.so.6
#23 0x0000007ff7bcde9c in ?? () from /lib/aarch64-linux-gnu/libc.so.6
```

The `libgallium` frames are unresolved (stripped distro build), so the exact Mesa call site that hands the pipeline to the driver cannot be named from this trace; the dump above (`filled quad gs`) is what identifies the path.

## Already ruled out (all measured on this board)

* Not vsync/presentation: `vblank_mode=0` → SIGABRT; `LIBGL_KOPPER_DRI2=1` → SIGABRT; `MESA_VK_WSI_PRESENT_MODE=immediate` → SIGABRT; `LIBGL_KOPPER_DISABLE=1` → SIGSEGV (Mesa 25.0.x, kopper path, different failure).
* `ZINK_DEBUG=noopt` → same abort, so it is not specific to an optimized shader form.
* Khronos validation layer, enabled correctly (without `VK_LAYER_PATH` shadowing the standard explicit-layer directories), reports **no** Vulkan API errors before the abort. TODO: exact `vk_layer_settings.txt`/validation-settings used for that run is not recorded.
* The layer is inert without its environment variable: same run without `PVR_FAKE_GS=1` gives the `w/o geometryShader is unsupported` message and no GL, no crash.
* Absence of DRI3 on the X server is irrelevant: DRI3/Present/DRI2 are present (`xdpyinfo`) and non-quad windowed GL works (`glmark2` on GLX).

## Suggestions

1. **Do not treat `VkPhysicalDeviceFeatures.geometryShader` as proof that GS pipelines are executable.** A probe at screen creation (create + destroy one trivial GS pipeline) would catch drivers that advertise the bit but cannot run a GS; when the probe fails, clear the GS-dependent caps (`supported_prim_modes`' `MESA_PRIM_QUADS`, `no_linesmooth`/`no_linestipple` emulation) instead of discovering it at draw time. This is driver-independent hardening and would not need a driver-ID list.
2. **Prefer a non-GS lowering for quads where one exists.** Mesa already ships topology conversion (`src/gallium/auxiliary/indices/u_primconvert.{c,h}`, included by other gallium drivers such as d3d12 and virgl) that turns `PIPE_PRIM_QUADS` into triangles with a generated index buffer, instead of allocating a geometry shader. TODO: we did not verify how this would fit zink's non-indexed `draw_vbo` path — that check needs a Mesa dev, we only measured the failure.
3. **Give the generated-GS paths an escape hatch** (driconf/`ZINK_DEBUG`-style switch) so that "no GS pipelines" can be forced on a driver where GS is advertised but fatal. Today the user's only choices are the abort or no zink at all.
4. **Reconsider the hard requirement for this driver ID.** `zink_screen.c:3457-3461` (25.0) refuses to initialize `VK_DRIVER_ID_IMAGINATION_PROPRIETARY` without `geometryShader`, and `zink_screen.c:2903-2907` sets `no_linesmooth` for the same ID with `assert(geometryShader)`. If that requirement is not strictly needed for correctness, initializing with `geometryShader = VK_FALSE` (and simply not advertising QUADS / not emulating smooth lines) would degrade gracefully instead of failing closed — on this driver the alternative is "no GL at all".

We are **not** asking Mesa to paper over a broken vendor driver: the abort is the vendor compiler's (`libufwriter.so` / `BILParseStream`), and the feature lie is ours, from a third-party layer. What we are reporting is the design point: zink converts ordinary fixed-function GL 2.1 content (`GL_QUADS`, no geometry shader anywhere in the app) into a real GS pipeline on the strength of one queried bit, and on this driver the failure mode of that decision is process abort with no Mesa-level diagnosis.

## Sources

* Mesa bug-reporting guidelines: https://docs.mesa3d.org/bugs.html · tracker: https://gitlab.freedesktop.org/mesa/mesa/-/work_items
* Mesa 25.0.7 sources cited above (`src/gallium/drivers/zink/zink_screen.c`, `zink_program.c`, `zink_compiler.c`; `src/gallium/auxiliary/indices/u_primconvert.c`)
* Vulkan feature-strip layer used to make this driver usable with zink: https://github.com/ayiejosh/a733-powervr-fex — `gpu/vk-feature-strip/`, `gpu/zink-trixie.md`
* Second published implementation of the same layer (not tested in this report): https://github.com/davidhfrankelcodes/pvr-a733-armbian
