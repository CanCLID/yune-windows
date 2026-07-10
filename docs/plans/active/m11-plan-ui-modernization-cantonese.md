# M11 UI Modernization + Cantonese Localization Plan

> **Status:** installed clone/drag proof passed on 2026-07-09 PT
> (2026-07-10 UTC); M11D activation/toggle/visibility reliability remains open.
> Slices A/B modernize and localize the native settings and toolbar surfaces.
> Slice C uses DirectComposition + Direct2D, fails closed on missing/invalid
> owners, arbitrates the visible toolbar within and across processes, and moves
> the HWND without presenting during drag. Native only; no WebView2.
>
> **2026-07-09 stabilization amendment:** a topology probe proved the screenshot
> was primarily multiple real toolbar HWNDs across processes, not merely painted
> ULW/DComp trails. The ownership, focus handoff, drag, and backdrop contracts
> below supersede the earlier assumption that changing presentation alone fixed
> cloning.

**Goal:** keep the first-party Windows 11/Cantonese UI while guaranteeing one
foreground-owned toolbar that drags without copies or focus steal. Acrylic is a
conditional enhancement; clone-free correctness comes first.

---

## Relationship to M10 (read first)

M10 owns skin breadth, catalog/import behavior, and candidate-window rendering.
M11 owns the toolbar stabilization and supplies only the reusable composition
device/surface foundation. Candidate rendering must not be counted as M11 scope.

**Stop-the-line dependency:** the installed clone/drag sub-gate passed, but no
M10 slice begins until M11D makes activation, lone-Shift state transition, and
eligible-host toolbar visibility deterministic and completes the four-host
installed gate. After that gate, M10 may generalize the composition lifecycle
for an opaque/static-tint candidate surface while preserving its independent
latency and fallback requirements.

---

## Current Facts (grounded)

- Slices A/B are implemented: common-controls v6/PerMonitorV2, JhengHei DPI
  relayout, guarded DWM settings polish, centralized Cantonese strings, combo
  label/value separation, and localized toolbar glyphs.
- Slice C uses `WS_EX_NOREDIRECTIONBITMAP`, DirectComposition, and Direct2D. The
  validated surface path keeps a fixed 96-DPI target and
  `D2D1_BITMAP_OPTIONS_CANNOT_DRAW`.
- A privacy-safe topology probe found six real `YuneWindowsLanguageBar_*` HWNDs
  across four processes. All were ownerless, and a background process could keep
  one visible. The clone problem therefore cannot be closed by renderer evidence
  alone.
- Missing TSF contexts now resolve through `ITfThreadMgr::GetFocus` and
  `ITfDocumentMgr::GetTop`. The last valid root owner, anchor, and DPI are cached
  while focused; contextless updates may reuse them but can never show or
  reparent an ownerless toolbar.
- Focus-service handoff is identity-aware. Process-local arbitration, the
  registered `YuneWindows.ToolbarSuperseded.v1` message, and a 250 ms foreground
  watchdog converge on at most one foreground-owned visible toolbar.
- Drag movement is HWND-only. All rendering/resource work during capture is
  queued and one non-reentrant finalizer persists the position once and flushes
  at most one render.
- The system-backdrop attribute is gated at Windows 11 build 22621. Rendering
  follows actual DWM success; failure and older builds use an opaque static pill.
- `glass_mechanism` and consumed `glass_fallback=static_tint` remain. The inert
  `glass_tint`, `glass_tint_opacity`, `blur_amount`, and
  `highlight_intensity` V1 fields are removed.

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

## Stabilization Risks

- **R1 — Backdrop requests can fail or trail even when topology is correct.**
  `DWMWA_SYSTEMBACKDROP_TYPE` is supported from build 22621. Cache actual DWM
  success and render an opaque static pill when it is unavailable. The installed
  gate, not the requested skin enum, decides whether acrylic remains the default.
- **R2 — Localized combo labels must stay separate from protocol values.** This
  split is implemented and remains a regression boundary: visible Cantonese text
  must never be sent as an `op=` schema/output/skin ID.
- **R3 — Multiple real toolbar windows outlive renderer changes.** The per-process
  TSF architecture needs fail-closed ownership, identity-aware focus handoff,
  process/cross-process arbitration, and the watchdog. A single real HWND can
  still exhibit a visual trail, so the live fallback order remains mandatory.

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
4. **Backdrop mechanism — UPDATED 2026-07-09:** request supported DWM Desktop
   Acrylic only on build 22621+, record effective success, and fall back to a
   fully opaque static pill. Clone-free behavior outranks glass. If acrylic trails
   with one real HWND, default to static-tint DComp; if static DComp trails, use a
   normally redirected opaque native D2D toolbar.
5. **M10 reconciliation — UPDATED 2026-07-09:** M11 supplies the reusable
   composition foundation, but M10 owns candidate rendering. The clone/drag
   sub-gate passed; no M10 work begins until M11D completes deterministic
   activation/visibility and the four-host installed gate.
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
1. Keep the native per-process TSF architecture and the existing
   `WS_EX_NOACTIVATE | WS_EX_NOREDIRECTIONBITMAP` DirectComposition surface.
2. Resolve missing contexts through `GetFocus` → `GetTop`, cache only valid root
   owners/anchors/DPI, and fail closed instead of showing or reparenting an
   ownerless toolbar.
3. Use identity-aware focused-service activation/deactivation with a
   per-service apartment dispatcher and activation generation, process-local
   single-visible arbitration, the registered supersession message, and the
   250 ms foreground watchdog. Hide on app deactivation and fully unregister on
   `WM_NCDESTROY`.
4. Make drag movement-only. Queue state, DPI, layout, backdrop, and device work
   during capture; centralize all capture-ending paths into one finalizer that
   persists once and renders once.
5. Gate DWM system backdrop at build 22621, require both frame-extension and
   backdrop success, and render the static fallback fully opaque. Handle
   same-size acrylic/static transitions without per-present DWM calls.
6. Keep only consumed V1 backdrop fields: `glass_mechanism` and
   `glass_fallback`. Remove inert tint/opacity/blur/highlight fields.
7. Add privacy-safe topology diagnostics and expanded non-elevated ownership,
   supersession, watchdog, destruction, and repeated-drag coverage.
8. Run the approval-gated installed host matrix. Apply the deterministic
   acrylic → static DComp → normally redirected opaque native D2D fallback if
   any visual-trail condition fails.

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
- **Backdrop honesty:** DWM Desktop Acrylic is optional presentation, not a
  correctness dependency. It is requested only at build 22621+, and the renderer
  uses it only when DWM reports success. The guaranteed result is an opaque static
  pill; the installed gate may demote or remove the toolbar DComp path if it trails.
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
| luna_pinyin_octagram | 朙月拼音（八股文）ⁱ | 朙 (**add case** — no fallthrough) |

ⁱ **Intentional (user-confirmed):** the full label renders `朙月拼音（八股文）`
(fully Cantonese) instead of yune-web's Latin `朙月拼音 + Octagram`. 八股文
("eight-legged essay") is the intended Cantonese rendering — a pun mirroring
"Octagram" ≈ "8-gram" ≈ 八股. Keeps the panel free of Latin and the no-ASCII
contract clean.

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
- [x] **Slice C:** DirectComposition + Direct2D toolbar presentation and device
  recreation path.
- [x] **Stabilization:** fail-closed root ownership, context recovery/cache,
  identity-aware focus-service handoff, process/cross-process arbitration,
  250 ms watchdog, deactivation/destruction cleanup.
- [x] **Drag:** movement-only `SetWindowPos`, deferred state/resource work, and
  one non-reentrant final flush/persist path.
- [x] **Backdrop/schema:** build-22621 gate, effective-state rendering, opaque
  static fallback, same-size transition cleanup, and removal of inert V1 fields.
- [x] Privacy-safe topology diagnostic and expanded non-elevated drag smoke.
- [x] Non-elevated TSF build and expanded language-bar smoke.
- [x] Approved installed Notepad/Chromium clone/drag proof: one stable,
  foreground-owned visible HWND and no user-observed copies/afterimages.
- [ ] M11D deterministic activation/toggle/visibility plus complete
  Notepad/Chromium/Explorer/Electron proof.
- [ ] Archive M11/M11C/M11D and unblock M10 only after M11D passes.

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
- Assert DWM backdrop calls are gated at build 22621, effective success controls
  opacity, static transitions clear the backdrop, and unchanged presents do not
  churn DWM calls.
- Assert ownerless show fails, focus handoff is identity-aware, the watchdog
  hides stale windows, drag movement does not render, and finalization renders
  and persists exactly once.
- Assert removed inert glass fields are rejected/absent.

## Completion Gates
- Settings panel renders themed Win11-native controls in JhengHei/Segoe, rounded
  corners + dark mode correct in light/dark, crisp at 100–200% DPI (Mica present
  but expected subtle on an opaque dialog).
- **No English remains** on any user-facing surface (panel, title, dialog
  captions + bodies, toolbar labels incl. ascii-active and octagram); terminology
  matches `uiText.yue`; server `op=` calls still work (label/value split verified).
- Installed topology shows at most one visible toolbar system-wide; every visible
  toolbar has a valid owner whose root is foreground.
- Repeated drag keeps one HWND, produces no clones/afterimages, never steals
  focus, persists one final position, and leaves the previous host hidden within
  250 ms after focus transfer.
- Acrylic is retained only if that gate passes. Otherwise follow the static DComp
  then normally redirected opaque native D2D fallback sequence.
- Candidate rendering is excluded from M11 and remains M10-owned.
- No WebView2/Electron/HTML; no engine/ABI change; `disable_learning` forced.
- Tier 3 remains a clean future option that Slices A/B set up.

## Remaining Decision Gate

The fresh clone/drag run retained acrylic because one stable visible HWND and no
visual copies/afterimages were observed. The static-DComp and redirected-D2D
fallbacks remain available if M11D regresses that result. The open gate is now
deterministic activation, exactly-once toggle acknowledgement, eligible-host
visibility, Explorer/Electron breadth, and host-restart position persistence.
Localization terminology is already implemented and is not reopened.
