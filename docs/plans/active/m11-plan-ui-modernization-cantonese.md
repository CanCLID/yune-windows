# M11 UI Modernization + Cantonese Localization Plan

> **Status:** active (non-elevated implementation in progress; live visual proof
> remains approval-gated). Modernizes the two native
> UI surfaces — the Win32 settings panel and the Direct2D floating toolbar — and
> localizes **all** user-facing text from English to written Cantonese, mirroring
> `yune-web`'s terminology. Stays native (no WebView2), consistent with D-15
> (native server-owned toolbar) and D-16 (native Win32 settings panel).
>
> **This draft was revised after a technical/localization/coherence review.** Two
> HIGH corrections are baked in: (1) the "glass" backdrop mechanism (a plain
> `CompositionBackdropBrush` does **not** blur what is behind a separate window),
> and (2) the settings combos couple *display text* to the *server value*, so
> localization needs a label/value split. Read the **Known Risks** section.

**Goal:** the settings panel should look like a first-party Windows 11 app
instead of a classic Win32 dialog; the toolbar should read as premium frosted
glass; and every string the user sees should be in Cantonese using `yune-web`'s
exact wording.

---

## Relationship to M10 (read first)

M10 (skin breadth + candidate-window skinning) is active and plans to migrate
`NativeCandidateWindow` GDI → shared Direct2D renderer + skin. M11's glass work
(Slice C) upgrades that *same* renderer to a DirectComposition surface. Building
the composition renderer twice is waste.

**Locked reconciliation (M10 already annotated):** M11 Slice C builds the shared
composition renderer **once** and applies it to the toolbar; the candidate-window
render migration (M10 Slice C) rides the same renderer instead of a separate
GDI→D2D pass. **Hard dependency (locked):** candidate-window skinning *waits on*
M11 Slice C — only M10 Slices A/B (second skin, user-imported skins, candidate
skin-schema fields) are independent and can land first. M10's Slice C map entry,
Design step 2, and task are annotated "deferred to M11 Slice C". The one part that
stays spike-dependent (Known Risk R3): the candidate window sits over app
*content* (not the wallpaper), so it may land on a simpler tinted surface rather
than the full `GlassSurface` — the Slice C spike decides *that*, not whether the
migration defers to M11 (it does).

---

## Current Facts (grounded)

- **Settings panel** (`src/tools/yune_windows_settings.cpp`) applies **zero**
  modernization: no common-controls v6 manifest (classic unthemed 3D controls),
  no font (falls back to the blocky `System` GUI font), no DWM attributes, no
  per-monitor DPI awareness. All labels are English `L"..."` literals. **The
  output/schema/skin comboboxes use the raw ID as the *visible item text*, and
  `SelectedComboText()` sends that exact visible text back to the server as the
  ID** (see Known Risk R2).
- **Toolbar** (`src/candidate_window/yune_windows_candidate_window.cpp`,
  `LanguageBarWindow` + `D2DSurface`) is `WS_EX_NOACTIVATE | WS_EX_LAYERED`, drawn
  with `ID2D1DCRenderTarget` into a DIB and presented via `UpdateLayeredWindow`
  (per-pixel alpha). ULW cannot sample/blur content behind the window (flat look).
  **The active-state segment glyphs are hardcoded C++ literals in
  `ToolbarSegmentLabelForState` / `SchemaLabel` / `OutputStandardLabel`, not skin
  manifest fields.** Today they emit `繁` (opencc), `港` (hk), `臺` (taiwan), `简`
  (mainland), `粵/倉/拼` per schema, and **`L"EN"` for ascii-active** — the one
  outright-English glyph. `SchemaLabel` has no `luna_pinyin_octagram` case and
  falls through to `value.substr(0,1)` → a Latin **`l`** leak.
- **Localization source of truth:** `yune/apps/yune-web/src/uiText.ts` (bilingual
  `yue` + `en`, **default `yue`**), plus `schemaText.yue`, `outputStandardText.yue`.
  Yune's Chinese name is **新韻**. Full mapping in the **String Mapping Appendix**.
- Build compiles `/utf-8 /DUNICODE /D_UNICODE`; wide `L"..."` literals in UTF-8
  source render Cantonese/Traditional glyphs (given a CJK font). `/W4`, no `/WX`.
- Settings exe links `/SUBSYSTEM:WINDOWS /ENTRY:wmainCRTStartup`;
  `dev-swap-tsf-dll.ps1` now redeploys it (M08/M09 follow-up).

## Non-Goals
- No WebView2 / Electron / HTML on any surface (D-15/D-16 hold).
- No engine/ABI change; `disable_learning` stays forced.
- No new *functional* controls — the scaffolded "coming soon" controls stay
  disabled; this milestone restyles + relabels them only.
- Not a pixel-clone of macOS "Liquid Glass" — Windows exposes blur + tint +
  highlight, not live refraction/lensing.
- Full bilingual runtime toggle is out of scope now (Decision 1).
- Tier 3 (fully custom-drawn D2D panel) is **not** in scope — but Slices A/B must
  not foreclose it.

## Known Risks (must read before implementing)

- **R1 — Blurring the live app behind the bar needs a specific path; the obvious
  one is wrong.** A *plain* `CompositionBackdropBrush` samples only the **same**
  window's visual tree — not the app behind a separate HWND — so it renders a
  hollow/transparent bar. The **supported** way to blur live content behind a Win32
  window is the **host backdrop brush**: `DwmSetWindowAttribute(hwnd,
  DWMWA_USE_HOSTBACKDROPBRUSH, TRUE)` (documented for **non-UWP** windows, Win11
  build **22000+**) filled by `Compositor.CreateHostBackdropBrush` (WinRT
  `Windows.UI.Composition`, which "samples the area behind the window"), with the
  window styled `WS_EX_NOREDIRECTIONBITMAP` so the composition shows through. This
  path has real setup friction and historically-reported flakiness — hence the
  community `SetWindowCompositionAttribute` `ACCENT_ENABLE_ACRYLICBLURBEHIND`
  workaround (undocumented but battle-tested; TranslucentTB et al.). The *supported
  DWM system backdrops* (`DWMSBT_MAINWINDOW` Mica, `DWMSBT_TRANSIENTWINDOW` Desktop
  Acrylic) blur the **desktop wallpaper**, not the live app — a weaker but fully
  stable look. **Decision (locked, Decision 4):** spike the **documented host
  backdrop brush first**, then the undocumented accent acrylic, then DWM wallpaper
  acrylic, then a static tint — never a hollow bar. Do **not** use a plain
  `CompositionBackdropBrush` for behind-window blur.
- **R2 — Combo display text == server value.** The output/schema/skin combos put
  raw IDs as visible text and `SelectedComboText()` round-trips that visible text
  to the server as the ID. Localizing the visible text **will break** `op=`
  calls unless the implementer separates *display label* from *value ID* (store
  the ID via `CB_SETITEMDATA` or a parallel array; look it up on selection).
- **R3 — `WS_EX_LAYERED`/ULW and a composition backdrop are mutually exclusive.**
  Moving the toolbar to DirectComposition means dropping `WS_EX_LAYERED` +
  `UpdateLayeredWindow`. Dropping them must not resurrect the M08/M09 clone-trail
  or focus-steal, and must re-achieve per-pixel-alpha click-through (see Slice C).

## Decisions (locked by user 2026-07-03 unless marked "reviewer confirm")
1. **Language scope — LOCKED: Cantonese-only now.** Strings centralized in one
   `ui_strings` header mirroring `uiText.yue` so an English toggle can drop in
   later, but **no runtime 粵/En switcher is built this milestone**.
2. **UI font:** `Microsoft JhengHei UI` primary (covers Traditional + acceptable
   Latin); this is the Tier-1 font decision, which is why localization is folded
   into the same slice. Toolbar keeps DirectWrite fallback but the manifest `font`
   should name a CJK-capable family.
3. **New terms not in `uiText.ts`:** `skin` → **主題** (HK-idiomatic; not 皮膚,
   which is a Mainland-software convention); `coming soon` → **（即將推出）**;
   `connected`/`offline` → **已連線 / 離線**; `default` (skin name) → **預設**;
   `Unknown` → **未知**. (Reviewer confirm wording.)
4. **Glass backdrop mechanism — LOCKED: live blur, supported path first.** The
   user chose live-content blur (not wallpaper-only). Implement via a **priority
   chain**: (1) **documented host backdrop brush** — `DWMWA_USE_HOSTBACKDROPBRUSH`
   + `Compositor.CreateHostBackdropBrush` (WinRT `Windows.UI.Composition`, Win11
   22000+, `WS_EX_NOREDIRECTIONBITMAP`); (2) undocumented
   `SetWindowCompositionAttribute` `ACCENT_ENABLE_ACRYLICBLURBEHIND` (battle-tested
   fallback); (3) DWM Desktop Acrylic (wallpaper blur, fully supported); (4) static
   translucent tint. **Never a hollow bar.** The Slice C spike measures which of
   (1)/(2) actually delivers on the target builds and locks the primary; it no
   longer chooses *whether* to have live blur. Do **not** use a plain
   `CompositionBackdropBrush` for behind-window blur (it can't reach behind).
5. **M10 reconciliation — LOCKED (M10 annotated):** build the composition renderer
   once; the candidate-window render migration defers to M11 Slice C. Only *whether*
   the candidate lands on the full `GlassSurface` vs a simpler tinted surface stays
   spike-dependent (R3 + candidate-over-content caveat).
6. **Output-standard glyphs:** `uiText.yue` is authoritative — change the C++
   literals (`繁→傳`, `臺→台`, `拼→朙`) and `L"EN"→英` to match the appendix.
7. **Windows 10 — LOCKED: flat-native fallback.** Glass/Mica/rounded are
   Win11-only and build-gated; **Windows 10 gets the clean themed look** (v6
   manifest + JhengHei font + dark mode) with **no glass/blur** and no attempt at
   the older composition path. Do not spend implementation/testing budget on Win10
   glass.

---

## Slice Map (sequence)

### Slice A — Native theming baseline + Cantonese strings (do together)
1. Add a **common-controls v6 manifest** embedded in `YuneWindowsSettings.exe`,
   declaring per-monitor-v2 DPI via the modern element (exact XML in Design
   Details). This themes every control (flat Win11 look) — the single biggest win.
2. Create one **`Microsoft JhengHei UI` `HFONT`** at window DPI; `WM_SETFONT`
   (LPARAM `TRUE`) onto every control; recreate + re-layout on `WM_DPICHANGED`.
3. Tidy layout: consistent margins, group-box spacing, control heights sized to
   the font. Keep the existing section structure.
4. Route **all** user-visible text through a centralized Cantonese `ui_strings`
   header (appendix); replace every inline English literal at
   `CreateWindowW`/`SetWindowTextW`/`MessageBoxW` call sites; window title +
   **error-dialog caption** → **新韻輸入法設定**.
5. **Combos (R2):** populate visible items with Cantonese labels but store the
   value ID via `CB_SETITEMDATA`/parallel array; `SelectedComboText` → look up the
   stored ID, not the visible text. Localize `OutputStandardLabel` and the
   composed status line (template in appendix).
6. **Toolbar literals (not just the manifest):** in
   `src/candidate_window/yune_windows_candidate_window.cpp`, edit
   `ToolbarSegmentLabelForState`/`SchemaLabel`/`OutputStandardLabel`: `L"EN"→英`,
   `繁→傳`, `臺→台`, `拼→朙`, and **add an explicit `luna_pinyin_octagram` case**
   (→ `朙`) so nothing falls through to `substr` (kills the Latin `l`/`EN` leaks).
   Align the default skin `theme.json` `segment_labels` to the same glyphs.

### Slice B — Windows 11 polish (DWM)
On the now-themed window, **gated by build number**:
- `DWMWA_SYSTEMBACKDROP_TYPE = DWMSBT_MAINWINDOW` (Mica) — **build ≥ 22621**.
- `DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND` — build ≥ 22000.
- `DWMWA_USE_IMMERSIVE_DARK_MODE` following the system theme — attribute value is
  **20** on Win11/Win10 20H1+ and **19** on Win10 1809–1903; set 20, fall back 19.
- Accent-colored primary elements; clean flat fallback on older builds.
- **Expectation caveat:** Mica behind an opaque control-filled dialog shows mostly
  as a subtly tinted background (DWM only shows material where the client area is
  transparent — full transparency requires custom-drawing control backgrounds =
  Tier 3, a non-goal). The real Win11 wins here are the v6 manifest + rounded
  corners + dark mode; treat Mica as a bonus, not the headline.

### Slice C — Glass toolbar (shared composition renderer; reconciled with M10)
1. **Spike first (de-risk R1/R3):** a throwaway proof, over a real editor window,
   on a `WS_POPUP | WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_NOREDIRECTIONBITMAP`
   window (**not** `WS_EX_LAYERED`), testing the R1 priority chain in order:
   (a) **documented** `DWMWA_USE_HOSTBACKDROPBRUSH` + `CreateHostBackdropBrush`
   (WinRT `Windows.UI.Composition`); (b) undocumented `SetWindowCompositionAttribute`
   `ACCENT_ENABLE_ACRYLICBLURBEHIND`; (c) DWM `DWMSBT_TRANSIENTWINDOW` acrylic
   (wallpaper); (d) static tint. Lock the first that blurs live content without
   artifacts. Confirm no focus-steal, no clone-trail, correct rounded click-through.
   Record findings + screenshots under `docs/evidence/m11/`.
2. Build a shared **`GlassSurface`** on the **WinRT `Windows.UI.Composition`
   compositor** interop'd to the HWND (`ICompositorDesktopInterop::CreateDesktopWindowTarget`)
   — this is the layer that exposes `CreateHostBackdropBrush`; raw
   `IDCompositionDevice` does not. Visual tree: backdrop-brush visual (host backdrop
   / accent per the spike) → content layer (existing `DrawLanguageBarContent` via a
   D2D/composition surface) → tint → rounded-rect composition clip → drop shadow →
   optional animated specular.
3. **Window model for the migration (R3):** create the popup
   `WS_POPUP | WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_NOREDIRECTIONBITMAP`
   (NOREDIRECTIONBITMAP is required or the DComp content shows a black rectangle;
   **not** `WS_EX_LAYERED`). Re-achieve per-pixel-alpha **click-through**: the
   transparent shadow/rounded-corner margins must return `HTTRANSPARENT` (or use a
   `SetWindowRgn`/input region) so clicks fall through to the app, while the pill
   body returns `HTCLIENT` for the drag — `WM_NCHITTEST → HTCLIENT` over the whole
   rect (today's behavior) would make the transparent margin swallow clicks.
   Preserve `MA_NOACTIVATE`, the `SetCapture` drag (verify it still works on a
   never-activating window), per-monitor DPI, monitor clamp, server-owned
   position/skin, and the **M08/M09 single-position-authority + drag-active guard**
   (no clone trail). Handle composition **device loss** (recreate the visual tree).
4. Extend the skin schema with **glass fields** (tint color + opacity, blur
   amount/mechanism, corner radius, highlight intensity, shadow) with back-compat
   defaults so existing manifests still load.
5. **M10 candidate window rides `GlassSurface`** (conditional — R3 + candidate
   sits over app content, so a wallpaper/live-blur backdrop may look weaker there;
   the spike must check the candidate case too, and it may end up a simpler tinted
   D2D surface). Preserve M04 caret anchoring/paging/owner-foreground guard;
   verify no latency regression vs the GDI version.

---

## Design Details

- **Manifest (exact):** embed both the v6 comctl32 dependency and the modern DPI
  element:
  ```xml
  <asmv3:application xmlns:asmv3="urn:schemas-microsoft-com:asm.v3">
    <asmv3:windowsSettings>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    </asmv3:windowsSettings>
  </asmv3:application>
  ```
  plus `<dependency>` on `Microsoft.Windows.Common-Controls` `6.0.0.0`. Use
  `<dpiAwareness>PerMonitorV2</dpiAwareness>` (2016 namespace) — **not** the older
  `<dpiAware>` element. A contract should assert the manifest is embedded.
- **Glass honesty (corrected):** the *documented host backdrop brush*
  (`DWMWA_USE_HOSTBACKDROPBRUSH` + `CreateHostBackdropBrush`) and the undocumented
  accent-acrylic path both blur the **live** content behind the bar; the DWM
  *system backdrops* (Mica/Acrylic) blur only the **desktop wallpaper**. A plain
  `CompositionBackdropBrush` reaches neither. Refraction/lensing is faked with edge
  gradients + specular. Set expectations by the path the spike locks.
- **DPI:** PerMonitorV2 + re-layout + font recreation on `WM_DPICHANGED`; the
  toolbar already handles DPI and must keep doing so through the renderer swap.
- **Fallback:** Slice B/C attributes are Win11-era; guard by build number and
  degrade to a clean flat (Slice A) look on Windows 10 rather than failing.
- **Accessibility:** keep native controls (combos, checkboxes) for keyboard/
  screen-reader support; only the toolbar (and any hero elements) are custom-drawn.

---

## String Mapping Appendix (locked terminology — from `uiText.ts`)

Source: `yune/apps/yune-web/src/uiText.ts` (`uiText.yue.*`, `schemaText.yue`,
`outputStandardText.yue`). Implement verbatim. Rows marked *derived* are composed
from those keys (not a single key) or are new terms per Decision 3.

**Product / window / status**
| English (current) | Cantonese | Source |
|---|---|---|
| Yune (product name) | 新韻 | `header.title` |
| Window title **and error-dialog caption** | 新韻輸入法設定 | derived (`settings.title`) |
| Native settings panel | 輸入法設定 | `settings.title` |
| Toolbar preview unavailable (line 510) | 工具列預覽無法顯示 | derived (new) |
| Status line (composed, lines 323–328) | 狀態：已連線 ｜ 傳統漢字 ｜ 主題：預設 | derived — see below |
| State: connected / offline | 已連線 / 離線 | new (Decision 3) |
| Unknown (output fallback) | 未知 | new (Decision 3) |
| Skin: `<name>` suffix; default → | 主題：預設 | new (Decision 3) |

Status-line template: `狀態：{已連線|離線} ｜ {output-standard full label} ｜ 主題：{skin}`.
The middle segment reuses the output-standard **full** labels below; `未知` if
unmapped; skin `default` shows `預設`.

**Section headers**
| English | Cantonese | Source |
|---|---|---|
| Input / session | 即時狀態 | `settings.sessionTitle` |
| Appearance | 顯示設定 | `settings.displayTitle` |
| Engine | 引擎設定 | `settings.engineTitle` |
| Dictionary | 用戶詞庫 | `userdb.title` |
| Schemas | 方案 | `toolbar.schema` |

**Input / session controls**
| English | Cantonese | Source |
|---|---|---|
| Mode: Chinese / English | 模式：中文 / 英文 | `settings.asciiMode`, `toolbar.chinese`/`ascii` |
| Shape: Full / Half | 字形：全形 / 半形 | `toolbar.fullShape`, `status.full`/`half` |
| Output standard | 輸出字形 | `settings.outputStandard` |
| Schema switch | 方案切換 | `toolbar.schema` |
| Extended charset (coming soon) | 擴展字集（即將推出） | `settings.extendedCharset` |
| Disable IME | 停用輸入法 | `settings.disabled` |

**Output standards** — full label (combo/status) and short glyph (toolbar).
The toolbar short glyph is a **C++ literal** (Slice A item 6), not a manifest field.
| ID (server value — do not translate) | Full label | Short glyph | Current code |
|---|---|---|---|
| opencc_traditional | 傳統漢字 | 傳 | was 繁 → change |
| hong_kong_traditional | 香港字形 | 港 | 港 (ok) |
| taiwan_traditional | 台灣字形 | 台 | was 臺 → change |
| mainland_simplified | 大陆简化字 | 简 | 简 (ok) |

**Schemas** (by RimeSchemaId — server value, do not translate)
| ID | Full label | Toolbar short glyph |
|---|---|---|
| jyut6ping3 | 粵語拼音 | 粵 |
| cangjie5 | 倉頡五代 | 倉 |
| luna_pinyin | 朙月拼音 | 朙 (was 拼 → change) |
| luna_pinyin_octagram | 朙月拼音 + Octagram | 朙 (**add case** — no fallthrough) |

**Appearance**
| English | Cantonese | Source |
|---|---|---|
| Skin | 主題 | new (Decision 3) |
| Candidate page size (coming soon) | 每頁候選詞數量（即將推出） | `settings.candidatesPerPage` |
| Candidate layout (coming soon) | 候選排版（即將推出） | `settings.candidateLayout` |
| Romanization display (coming soon) | 候選粵拼（即將推出） | `settings.candidateJyutping` |

**Engine (all coming soon)**
| English | Cantonese | Source |
|---|---|---|
| Completion | 自動補詞 | `settings.autoCompletion` |
| Correction | 自動校正 | `settings.autoCorrection` |
| Sentence mode | 自動組句 | `settings.autoComposition` |
| Prediction | 預測不排第一 | `settings.predictionNeverFirst` |
| Combine candidates | 合併同字候選 | `settings.combineCandidates` |

**Dictionary / Schemas / actions**
| English | Cantonese | Source |
|---|---|---|
| Import userdb (coming soon) | 匯入用戶詞庫（即將推出） | `userdb.importRaw` + `userdb.title` |
| Export userdb (coming soon) | 匯出用戶詞庫（即將推出） | *derived* (`userdb.title`; `匯出` is derived — `userdb.downloadRaw` = 下載) |
| Installed schema switching is available above. | 已安裝方案可喺上面切換。 | derived |
| Import schema (coming soon) | 匯入方案（即將推出） | `userdb.importRaw` + `toolbar.schema` |
| Refresh | 刷新 | `userdb.refresh` |

**Error dialogs (bodies)**
| English | Cantonese |
|---|---|
| Yune Windows server is not available. | 新韻輸入法伺服器未啟用。 |
| Unable to update Yune Windows state. | 無法更新輸入法狀態。 |
| Unable to update Yune Windows schema. | 無法更新方案。 |
| Unable to update Yune Windows skin. | 無法更新主題。 |

(Caption for all four → 新韻輸入法設定, per the product/window table.)

**Toolbar segment labels (default skin + C++ literals)**
| Segment | Cantonese |
|---|---|
| ascii mode | 中 / 英 (was 中 / **EN** → change the `L"EN"` literal) |
| full shape | 全 / 半 |
| output standard | 傳 / 港 / 台 / 简 (per active standard; C++ literals) |
| schema | 粵 / 倉 / 朙 (per active schema; add octagram case) |
| settings | ⚙ (glyph) |

---

## Tasks
- [x] **Slice A:** v6 common-controls manifest + PerMonitorV2 (modern element);
  JhengHei `HFONT` on all controls (recreate on DPI change); layout tidy.
- [x] **Slice A:** centralized Cantonese `ui_strings`; replace all panel literals;
  title + dialog caption 新韻輸入法設定; **combo label/value split (R2)**;
  localized `OutputStandardLabel` + status-line template.
- [x] **Slice A:** toolbar C++ literal fixes (`EN→英`, `繁→傳`, `臺→台`, `拼→朙`,
  add octagram case) + align default `theme.json` segment glyphs.
- [x] **Slice B:** DWM Mica (≥22621) + rounded (≥22000) + dark-mode (20↦19) +
  accent; Win10 flat fallback; document Mica-on-opaque-dialog expectation.
- [x] **Slice C spike:** compare acrylic-blur-behind vs DWM acrylic vs static tint
  on a no-activate topmost popup **without WS_EX_LAYERED**; evidence + screenshots
  under `docs/evidence/m11/`; pick the mechanism. Non-elevated evidence records
  the priority chain and keeps live screenshots approval-gated.
- [x] **Slice C:** shared `GlassSurface` shell with the DComp
  `WS_EX_NOREDIRECTIONBITMAP` host-backdrop path documented/guarded, explicit
  fallback ordering, and toolbar migration through the shell while keeping
  no-activate/drag/DPI/position/skin + M08/M09 clone-trail invariants and device
  loss recovery. The checked-in shell preserves the existing layered Direct2D
  fallback until live TSF-host visual proof approves a full DComp style swap.
- [x] **Slice C:** skin schema glass fields + back-compat; candidate window (M10
  Slice C) rides `GlassSurface` **if** the spike supports it; latency check vs M04.
- [x] Contracts (see below). Evidence under `docs/evidence/m11/`.
- [x] Roadmap / decisions / README updates; **annotate M10 Slice C**. Commit to `main`.

## Contract coverage (sharpened)
Because contracts are source-grep PowerShell, a blanket "no English" grep would
false-positive on legitimate ASCII (`op=` verbs, `schema_id`s like `jyut6ping3`,
`output_standard` values, DWM/DPI API names). Instead:
- Assert the v6 manifest + `PerMonitorV2` element are embedded/declared for the
  settings exe.
- Assert all user-visible text routes through the `ui_strings` header, and that
  **no user-facing `CreateWindowW`/`SetWindowTextW`/`MessageBoxW` call site uses an
  inline `[A-Za-z]` `L"..."` literal** (not a whole-file grep).
- Assert `ui_strings` display values contain no unintended ASCII letters.
- Assert `SchemaLabel`/`ToolbarSegmentLabelForState` have no `substr` fallthrough
  and no `L"EN"`/Latin glyph for any known schema/standard.
- Assert combos store value IDs separately from display text (label/value split).
- Assert DWM attribute calls are build-gated; assert toolbar keeps `WS_EX_NOACTIVATE`,
  single-position-authority, and drag-active guard after the renderer swap.
- Assert a toolbar-only skin still loads (glass-field back-compat).

## Completion Gates
- Settings panel renders themed Win11-native controls in JhengHei/Segoe, rounded
  corners + dark mode correct in light/dark, crisp at 100–200% DPI (Mica present
  but expected subtle on an opaque dialog).
- **No English remains** on any user-facing surface (panel, title, dialog
  captions + bodies, toolbar labels incl. ascii-active and octagram); terminology
  matches `uiText.yue`; server `op=` calls still work (label/value split verified).
- Toolbar shows a frosted-glass look — **live blur of the content behind the bar
  (host backdrop brush `DWMWA_USE_HOSTBACKDROPBRUSH`/`CreateHostBackdropBrush`, or
  the accent-acrylic fallback) + tint + rounded + shadow + specular**, with
  graceful fallback to wallpaper acrylic / static tint if a build breaks it — still
  no-activate, drags as a single bar with no clone trail, persists position.
- Candidate window (if folded in) matches the active skin with no latency
  regression vs M04.
- No WebView2/Electron/HTML; no engine/ABI change; `disable_learning` forced.
- Tier 3 remains a clean future option that Slices A/B set up.

## Reviewer Questions
**Decided/locked:** glass = **live blur, documented host backdrop brush first**
(Decision 4); language = **Cantonese-only now** (Decision 1); Win10 =
**flat-native fallback, no glass** (Decision 7); M10 render-migration **defers to
M11 Slice C** (Decision 5, M10 annotated). Remaining open items:
- Confirm new terms: 主題 (skin), 即將推出, 已連線/離線, 預設, 未知, and the
  derived strings (window title, status-line template, "已安裝方案可喺上面切換。",
  error bodies/caption, 工具列預覽無法顯示).
- Confirm output-standard glyph change 繁→傳 (mirror `uiText.yue`) and the
  toolbar literal edits (EN→英, 臺→台, 拼→朙, add octagram 朙).
