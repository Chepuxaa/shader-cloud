# Shaders cloud library

HLSL effects and declarative controls for the independent Skybox, Weapon and
Autopeek Fatality Lua clients. This repository distributes JSON and HLSL only;
the standalone Lua clients contain their native bridges.

| Client | Catalog | Style files |
| --- | --- | --- |
| Skybox | `skybox/manifest.json` | `skybox/styles/<id>.json` and `.hlsl` |
| Weapon | `weapons/manifest.json` | `weapons/styles/<id>.json` and `.hlsl` |
| Autopeek | `autopeek/manifest.json` | `autopeek/styles/<id>.json` and `.hlsl` |

**All styles use descriptor `contract: 2`.** Update the three Lua clients before
using this library. Contract-1 styles and their parameter transport have been
retired; older clients cannot load the current styles. Previous library contents
remain in Git history.

## Editing and refreshing

Every style has exactly one JSON and one HLSL file. Edit those files in place;
there are no numbered files or per-effect revisions. For example, edit
`autopeek/styles/glass.json` to change its controls or its `.hlsl` to change the
appearance. Commit the replacement, then press **Refresh library** in Autopeek.

Refresh downloads the catalog and current style again and marks other cached
styles for a fresh download when selected. Requests have cache-busting queries.
A failed download, validation or compilation preserves the working effect.
Compatible user settings survive refresh; changed control types use defaults.
Cached compatible styles remain available without HTTP.

To add a style, create `<id>.json` and `<id>.hlsl` in its section's `styles`
directory. Name and author come from JSON:

```json
{
  "contract": 2,
  "id": "example",
  "name": "My effect",
  "author": "Your name",
  "order": 50,
  "controls": []
}
```

The list displays **My effect (by Your name)** and searches both fields. IDs use
lowercase letters, digits, underscores and hyphens and must match both filenames.
Name and author allow up to 48 and 32 UTF-8 bytes. Lower `order` sorts first
(default 1000), with ID as the tie-breaker.

### Automatic catalogs

Do not edit `manifest.json` manually. The **Build style manifests** GitHub Actions
workflow validates all three libraries on push to `main` and commits any catalog
changes as `github-actions[bot]`. It also validates pull requests without writing.
The Actions page provides **Run workflow** for a manual rebuild.

A catalog still has `contract: 1`: that number describes the ID/name/author list,
not a shader descriptor or its GPU layout. It does not enable contract-1 styles.
Changing a style name/author updates the list; deleting both files removes it.
Missing pairs, malformed JSON, invalid controls, overlaps and file-size limits
stop validation before catalog writes. The workflow validates source restrictions;
it does not compile HLSL or prove its appearance in game.

If branch rules prevent a bot commit, generate and commit the catalog locally
or grant the workflow access. The workflow never force-pushes.

```text
python -m unittest discover -s tests -v
python scripts/build_manifests.py
python scripts/build_manifests.py --check
```

Python 3.10+ needs no external dependencies for those checks. In the client
workspace, optional `lupa` compares the Python schema with
`tools/cloud_parameter_contract.lua`. That integration comparison is skipped in
a standalone library clone. Set `CLOUD_PARAMETER_CONTRACT_LUA` when the helper
lives elsewhere.

## Controls and slots

Each control has a unique `key`, a `label`, a `type`, a `default`, and either a
one-based scalar `slot` or an engine `binding`.

| Type | Additional fields | Published value |
| --- | --- | --- |
| slider | min, max, step, optional scale | displayed value multiplied by scale |
| select | options | zero-based selected index |
| checkbox | boolean default | 0 or 1 |
| color | RGB default | three consecutive normalized floats |

`group` is `main` or `colors`. Slots cannot overlap. A color at slot 16 occupies
16, 17 and 18. Gaps contain zero. Slot count is inferred from the greatest
occupied endpoint; no `slot_count` field or Lua change is needed for 18, 30 or
other counts. Zero user slots are valid.

The maximum is **16368 user floats**, from DX11's 64 KiB constant-buffer limit
minus 16 frame floats. A color can start no later than slot 16366. Buffers are
padded to four floats, with a minimum of one user `float4` (80 bytes total for a
zero-slot style). JSON is limited to 32768 bytes and HLSL to 65536 bytes. Selects
have 1..16 options; catalogs contain up to 24 styles.

Slider numbers and optional scale must be finite with magnitude at most 100000;
scale must be nonzero. Scaled slider endpoints must have magnitude below 1e9.

### Engine bindings

`binding: "speed"` is one slotless slider with a range inside 0..300. Its displayed
percentage is unscaled: 100 means normal animation speed.

Autopeek also accepts slotless `radius` and `opacity` sliders. Their values use
`scale`; physical radius is clamped to 8..128 world units and opacity to 0..1.
Absent bindings default to radius 42 and opacity 1. Bindings must be unique,
cannot declare a slot, and cannot use other control types.

Published Autopeek radii start at **50%**. Keep the default at 50 and set `scale`
to the desired world radius divided by 50:

```json
{
  "key": "radius", "label": "Radius", "type": "slider", "binding": "radius",
  "min": 10, "max": 100, "step": 1, "default": 50, "scale": 0.84
}
```

| Scale | Radius at 50% |
| --- | ---: |
| 0.60 | 30 |
| 0.84 | 42 |
| 1.00 | 50 |

Each shader may draw a different proportion inside that carrier. Slots named
`radius` or `opacity` without an engine binding are ordinary user parameters.

## Generated HLSL interface

The client prepends a generated constant buffer at pixel-shader register `b6`.
Do not redeclare that buffer or generated `SC_*` names. Weapon transparently remaps
authored `b6` to its private `b7` slot.

| Helper | Result |
| --- | --- |
| `SC_SLOT_COUNT` | inferred scalar count, as a compile-time constant |
| `SC_Get(uint slot)` | one-based user scalar; zero outside 1..count |
| `SC_Color(uint startSlot)` | three consecutive scalars as `float3` |
| `SC_Time()` | animation seconds, affected by speed |
| `SC_Clock()` | frame clock |
| `SC_Opacity()` | engine opacity |
| `SC_ReleaseAge()` | Autopeek seconds since release; -1 while held |
| `SC_IsOccluded()` | Autopeek compile-time pass flag; true behind scene geometry |
| `SC_FrameViewport()` | `float4(viewportX, viewportY, width, height)` |
| `SC_FrameCamera()` | `float4(pitch, yaw, roll, tanHalfVerticalFov)` |
| `SC_FrameAnchor()` | `float4(anchorX, anchorY, anchorZ, radius)` |

Camera angles use degrees. Autopeek calibrates the vertical tangent; Skybox and
Weapon supply the reference 0.75 tangent. The header contains four `float4`
vectors (time/clock/opacity/release age, viewport, camera, anchor), followed by
packed user vectors. All user slots remain available in every section.
`SC_IsOccluded()` returns false in Skybox and Weapon, which have no occluded pass.

### Skybox

Targets `ps_5_0`, with world-facing direction in `TEXCOORD0`:

```hlsl
struct Input { float3 dir:TEXCOORD0; float4 pos:SV_Position; };
float4 main(Input i):SV_Target0 { return float4(SC_Color(1),1); }
```

Add a color at slot 1 to that example's JSON. Included styles are Lines, Galaxy,
Retro and Portal; Gradient is embedded in the Lua. A Static mode must ignore
`SC_Time()` in HLSL.

### Weapon

Targets `ps_5_0` and replaces `csgo_weapon.vfx_ps`. Hologram reads the original
local-position `TEXCOORD8`; Galaxy reads pixel position and frame-camera metadata.
Do not add vertex-input dependencies that the original draw does not supply.

Comic uses geometric shading bands, a dark inner rim and an antialiased print-dot
pattern. It has four editable palette colors, 2..6 shading levels and controls for
ink, halftone, dot spacing, shadow lift and highlights. It uses the existing pixel
position and frame metadata, without new textures or render passes. Its ink stays
inside the model silhouette; this material replaces the original skin's colors.

### Autopeek

Targets `ps_4_0` and receives normalized local UV coordinates:

```hlsl
struct Input { float4 pos:SV_POSITION; float4 col:COLOR0; float2 uv:TEXCOORD0; };
float4 main(Input i):SV_Target {
    float2 p=i.uv*2-1;
    float opacity=saturate(1-length(p));
    return float4(SC_Color(1),opacity*i.col.a);
}
```

`i.col.rgb` is white; `i.col.a` already includes activation fade and the opacity
binding. Apply global opacity once, using either `i.col.a` or `SC_Opacity()`;
do not multiply both. Read colors with `SC_Color`. There are no integer UV
offsets; time and release age come from the named helpers. Published Ripples/Halo
preserve their existing animation cadence and cycle math locally in HLSL.

Autopeek renders world geometry using the selected scene's hardware depth test.
The same HLSL is compiled for visible and occluded passes. Authors may optionally
query `SC_IsOccluded()` to change the effect behind geometry; no JSON flag is
needed. A shader that does not query it uses the same effect in both passes.
The generated header defines `SC_OCCLUDED_PASS` as 0 or 1, so this branch is a
compile-time choice. Glass reuses its own rim in the occluded pass and keeps its
blurred interior in the visible pass. Its `#ifndef SC_OCCLUDED_PASS` compatibility
guard supplies a visible-only helper for older client headers.

The vertex shader owns `b1/b2` for camera and geometry. Scene depth and viewport
are selected at runtime; separate viewmodel passes must not replace them.
Controlled-device checks cover several sample counts and formats; in-game
compatibility still needs testing.

`capture_background: true` binds a scene image at `t0` with sampler `s0`. Glass
keeps this flag for its visible blur; `SC_IsOccluded()` does not enable background
capture. Glass also reads the native 80-byte `b0` GUI-layout buffer
(`float4x4 mvp; float2 tex;`)
for viewport/background dimensions. The captured image may include HUD already
rendered at capture time; depth masking alone cannot separate that content.

Published styles are Ripples (polygon ring and trailing waves), Glass (circular
rim and blurred scene), Radial (soft center glow), and Halo (by Codex: contour,
orbiting highlights and a restrained inner pulse).

Authoring examples in [`examples/autopeek`](examples/autopeek), `three_color_18`
and `three_color_30`, demonstrate three independent colors, slots beyond 15 and
the three engine bindings. They are excluded from the live catalog. Copy a
JSON/HLSL pair into `autopeek/styles` to publish it after testing.

## Permissions and testing

Clients require FFI and HTTP. Filesystem access is optional for offline caching.
Use one Lua per category; each owns its own tab. Development tools are not
required by users. Cloud files never execute Lua or native modules.

Owned-device fixtures compile and exercise parameter transport and rendering
without attaching to CS2. Actual appearance still needs validation in Fatality.
Marketplace approval and future engine-update compatibility are not promised.
