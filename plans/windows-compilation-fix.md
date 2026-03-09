# Windows Compilation Fix Plan

## Context

The repository was restructured (PR #947) moving content from `private-repo-import/` to the root.
iOS/macOS (Phase 3) and Android (PR #948) builds have been fixed. Windows (Phase 7) is still broken.

The Windows VS project lives at `clients/windows/Projet/vs2019/`.

### Path depth reference
- From `vs2019/` → repo root = `..\..\..\..\` (4 levels)
- From `vs2019/{subdir}/` (ParticubesWin, xptools, lpng, harfbuzz, freetype) → repo root = `..\..\..\..\..\` (5 levels)

### Root cause
Two issues:
1. **`cubzh\` prefix in paths**: The old structure had a `cubzh/` subdirectory. Now that content is at repo root. Replacing `cubzh\X` with just `X` AND adding one extra `..` level resolves this.
2. **Non-cubzh paths also have wrong depth**: Some paths (harfbuzz, freetype, a pthread ref in ParticubesWin) already lack the `cubzh\` prefix but still point to `clients/deps/` instead of repo root `deps/`.

---

## Phase 1: Fix `.vcxproj` files with `cubzh\` prefix (499 occurrences, 7 files) ✅

### 1a. Files in `vs2019/` root (bgfx, bimg, bx, glfw) ✅

These use `..\..\..\cubzh\` which should become `..\..\..\..\`:

| File | Occurrences |
|------|-------------|
| `bgfx.vcxproj` | 83 |
| `bimg.vcxproj` | 52 |
| `bx.vcxproj` | 94 |
| `glfw.vcxproj` | 25 |

**Replacement:** `..\..\..\cubzh\` → `..\..\..\..\`

### 1b. Files in `vs2019/{subdir}/` (ParticubesWin, xptools, lpng) ✅

These use `..\..\..\..\cubzh\` which should become `..\..\..\..\..\`:

| File | Occurrences |
|------|-------------|
| `ParticubesWin/ParticubesWin.vcxproj` | 127 |
| `xptools/xptools.vcxproj` | 93 |
| `lpng/lpng.vcxproj` | 25 |

**Replacement:** `..\..\..\..\cubzh\` → `..\..\..\..\..\`

---

## Phase 2: Fix `.vcxproj.filters` files (481 occurrences, 7 files)

Same replacements as Phase 1, applied to the corresponding `.filters` files:

| File | Occurrences |
|------|-------------|
| `bgfx.vcxproj.filters` | 81 |
| `bimg.vcxproj.filters` | 50 |
| `bx.vcxproj.filters` | 92 |
| `glfw.vcxproj.filters` | 23 |
| `ParticubesWin/ParticubesWin.vcxproj.filters` | 119 |
| `xptools/xptools.vcxproj.filters` | 91 |
| `lpng/lpng.vcxproj.filters` | 25 |

---

## Phase 3: Fix non-cubzh broken paths

### 3a. `harfbuzz/harfbuzz.vcxproj` — wrong depth (no cubzh prefix)
- Current: `..\..\..\..\deps\` (4 levels → `clients/deps/`)
- Correct: `..\..\..\..\..\deps\` (5 levels → repo root `deps/`)

### 3b. `freetype/freetype.vcxproj` — mixed paths
- Some configs use `..\..\..\include` (3 levels, old internal freetype path)
  - Should be: `..\..\..\..\..\deps\freetype\include`
- Some configs already use `..\..\..\..\deps\freetype\include` (4 levels → `clients/deps/`)
  - Should be: `..\..\..\..\..\deps\freetype\include`

### 3c. `ParticubesWin/ParticubesWin.vcxproj` — pthread path without cubzh
- Current: `$(ProjectDir)..\..\..\..\deps\pthread\` (4 levels → `clients/deps/`)
- Correct: `$(ProjectDir)..\..\..\..\..\deps\pthread\` (5 levels → repo root)

---

## Phase 4: Fix pre-build scripts and special paths

### 4a. `xptools/xptools.vcxproj` — env script path (lines 68, 92)
- Current: `..\..\..\..\env\convert_env_to_header.ps1`
- Correct: `..\..\..\..\..\scripts\convert_env_to_header.ps1`
  (The script is at `scripts/convert_env_to_header.ps1`, and we need 5 `..` from xptools/)

### 4b. `xptools/xptools.vcxproj` — stale grpc/tracking reference
- Current: `..\..\..\..\grpc\tracking` in AdditionalIncludeDirectories
- The tracking code is Go, not C++. This appears stale.
- **Action:** Remove this include path entry, or verify if there were C/C++ tracking headers before the restructure.

### 4c. `ParticubesWin/ParticubesWin.vcxproj` — pre-build deptool command
- Current: `cd ..\..\..\..\cubzh\deps\deptool\cmd && deptool_windows_x86_64.exe autoconfig windows`
- Correct: `cd ..\..\..\..\..\deps\deptool\cmd && deptool_windows_x86_64.exe autoconfig windows`

### 4d. `ParticubesWin/ParticubesWin.vcxproj` — hasher path
- Look for `cubzh\deps\hasher\` references and replace similarly.

---

## Phase 5: Fix resource file

### 5a. `ParticubesWin/ParticubesWin.rc` — icon path
- Current: `..\\..\\..\\..\\cubzh\\misc\\icon_circle.ico`
- Correct: `..\\..\\..\\..\\..\\misc\\icon_circle.ico`

---

## Phase 6: Fix scripts and Docker

### 6a. `clients/windows/generate_bundle.bat` (4 occurrences)
- Current: `cubzh\deps\xptools\windows`, `cubzh\bundle`, `cubzh\lua\modules`, `cubzh\i18n`
- Fix: Remove `cubzh\` prefix. Verify the path depth from where the bat is invoked.

### 6b. `clients/windows/bundle-builder/Dockerfile` (3 occurrences)
- Current: references to `/cubzh/bundle`, `/cubzh/i18n`, `/cubzh/lua/modules`
- Fix: Remove `cubzh/` prefix from COPY/path references.

### 6c. `clients/windows/generate-icons/run.sh` (1 occurrence)
- Fix: Remove `cubzh` prefix.

---

## Phase 7: Verification

1. Open `Blip.sln` in Visual Studio
2. Build Debug|x64 configuration
3. Fix any remaining include/link errors iteratively
4. Build Release|x64 configuration
5. Verify the pre-build steps (deptool, env header generation) execute correctly

---

## Notes

- **sbs.vcxproj** is NOT in the solution and references many files that no longer exist (`common/engine/`, `common/CUtils/`, `common/Lua/`, etc.). It is a **stale legacy project** — skip it.
- The solution references 9 projects: Blip (ParticubesWin), bgfx, bimg, bx, glfw, xptools, lpng, harfbuzz, freetype.
- The approach mirrors what was done for Android (PR #948): systematic path replacement + depth adjustment.
