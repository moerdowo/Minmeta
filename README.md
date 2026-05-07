# Minmeta

A native macOS app that fills in missing ID3 / iTunes metadata for your music
library. iTunes' own catalog is the primary source — drop a file or folder
in, and Minmeta searches Apple's free public Search API for each track and
writes title / artist / album / album-artist / year / genre / track number
back into the file.

For tracks that **aren't** in Apple's catalog (bootlegs, demos, very obscure
indie) or whose **filenames are too messy** to identify (`audio_export.mp3`,
`01 - track 1.mp3`, random YouTube ID stubs), an optional OpenAI-compatible
model can be plugged in as a fallback. iTunes is consulted again for cover
art after the model returns.

> ⚠ **Heads-up about accuracy.** AI-suggested metadata can be wrong —
> especially for ambiguous filenames, covers, live versions, regional
> releases, or anything outside the well-documented mainstream. Always
> spot-check the results in your music player before trusting them.
> Minmeta writes whatever the model returns; it does not double-check.
> If the AI produces nothing or you don't trust it, leave the API key
> blank and Minmeta will run iTunes-only — anything iTunes can't find
> is left untouched.

<p align="center">
  <img src="docs/screenshots/main.png" alt="Minmeta — Winamp-style UI with drop zone and queue" width="540">
</p>

## Resolution flow

For each file:

1. **Read** existing tags + technical info via AVFoundation.
2. **Hint extraction** — pull artist / title / album from existing tags first,
   then from the filename (handles `Artist - Title`, `01 - Title`,
   `01. Artist - Title`, strips `[Official Video]` / YouTube IDs etc.) and
   the last 1–2 parent folder names.
3. **iTunes Search** — query the `song` entity, score the top 5 hits against
   the hints, take the best match. **If the artist+title score ≥ 4** (one
   field matched exactly OR both as substring) iTunes is trusted as the
   primary source.
4. **AI fallback** — only if iTunes scored too low **and** an API key is
   configured: ask the model to interpret the filename, then re-query iTunes
   with the model's canonical artist/title for cleaner art and any final
   backfill.
5. **Skip** — if neither iTunes nor AI produced metadata (or no key is set
   for the AI fallback), the file is marked `SKIPPED · NO ITUNES MATCH ·
   SET API KEY IN CFG TO ENABLE AI FALLBACK`. Existing tags stay intact.

The queue UI shows which path each row took: a `ITUNES · …` prefix in the
detail line means iTunes was the source; `AI · …` means the model was used.

## Fields written

| Field         | iTunes | AI fallback |
|---------------|--------|-------------|
| Title         | ✓      | ✓           |
| Artist        | ✓      | ✓           |
| Album         | ✓      | ✓           |
| Album artist  | ✓      | ✓           |
| Year          | ✓      | ✓           |
| Genre         | ✓      | ✓           |
| Track number  | ✓      | ✓           |
| **Composer**  | —      | ✓           |
| **Copyright** | —      | ✓           |
| Cover art     | ✓ (600 × 600 JPEG)        | ✓ (re-queries iTunes) |
| Lyrics (USLT) | —      | —           | (writer infrastructure exists, neither source populates it) |
| Bitrate / sample rate / duration / channels / codec | shown read-only | shown read-only |

## File formats

| Format          | Read | Write                                                                     |
|-----------------|------|---------------------------------------------------------------------------|
| MP3             |  ✓   | ✓ ID3v2.3 — TIT2 TPE1 TALB TPE2 TYER TCON TRCK TCOM TCOP USLT APIC        |
| M4A / MP4 / AAC |  ✓   | ✓ via `AVAssetExportSession` passthrough + atomic replace                  |
| FLAC / WAV / AIFF / OGG | ✓ | — marked `SKIPPED`; suggestion is still shown in the queue row        |

## Build

Requires macOS 14+ and the Swift toolchain that ships with Xcode 15+.

```bash
./build.sh
open build/Minmeta.app
```

The script regenerates `App/AppIcon.icns` if `App/icon-source.png` is newer,
runs `swift build -c release`, and produces an ad-hoc-signed
`build/Minmeta.app`.

## Usage

1. Launch the app — it boots straight into the main UI in **iTunes-only
   mode** by default. No login.
2. *(Optional)* click the `CFG` button in the title bar to open the
   settings window and add an OpenAI-compatible API key. The status bar
   in the main panel will show `AI: gpt-4o-mini · FALLBACK READY`. Click
   `FORGET KEY` to go back to iTunes-only.
3. Drop files / folders onto the dropzone, or click `BROWSE…`. Folders are
   walked recursively for supported extensions.
4. Each row goes through the phases **WAIT → READ → ITNS → (AI if fallback)
   → TAG → DONE**. The LED pulses through phase-coloured states and a
   per-row progress bar shimmers during the long phases. 3 files run in
   parallel.
5. **Buttons** — `CLEAR` empties the queue (keeps in-flight items),
   `REMOVE DONE` purges completed/skipped rows, `RETRY FAILED` re-queues
   anything that errored.

## Privacy

- The optional API key is stored at
  `~/Library/Application Support/Minmeta/credentials.json` (mode 0600,
  owner-only). The macOS Keychain is not used: every ad-hoc rebuild has a
  different code signature, which would prompt the "Allow / Always Allow"
  dialog on each launch.
- For each track, **filename + parent folder names + existing tags** are
  sent to `https://itunes.apple.com/search` (Apple, no key) and — only on
  the AI-fallback path — to your configured OpenAI base URL. **Audio bytes
  never leave the machine.**
- Album art is downloaded from Apple's iTunes CDN (whatever URL the search
  result links to) and embedded locally.

## Layout

```
Sources/Minmeta/
├── MinmetaApp.swift              # @main + RootView + Settings Window scene
├── AppState.swift                # ObservableObject, queue, models
├── Theme.swift                   # Winamp colour palette + bevel modifiers
├── Views/
│   ├── Panel.swift               # reusable Winamp-style panel chrome
│   ├── MainScreenView.swift      # drop zone + status + activity meter
│   ├── QueuePanelView.swift      # playlist-style queue with live updates
│   └── SettingsWindowView.swift  # API key + base URL + model + FieldRow
└── Services/
    ├── CredentialsStore.swift    # 0600 JSON file in Application Support
    ├── MetadataReader.swift      # AVFoundation tag + tech-info read
    ├── ITunesArtClient.swift     # iTunes Search → match + 600×600 JPEG
    ├── OpenAIClient.swift        # /chat/completions JSON-mode prompt
    ├── ID3Writer.swift           # ID3v2.3 frame writer (incl. APIC, USLT)
    ├── M4AWriter.swift           # AVAssetExportSession passthrough
    └── ProcessingEngine.swift    # iTunes-first flow + AI fallback
Tools/
└── make_icon.swift               # source PNG → AppIcon.iconset (squircle)
```

## Notes

- Style inspiration: classic Winamp 2.x — title bars with control dots, LCD
  green-on-black readouts, beveled buttons, monospaced pixel text. The icon
  shape is a 22.37 % rounded-rect (close enough to Apple's continuous-corner
  squircle that it's indistinguishable at icon resolutions).
- Concurrency is a worker-pool of 3 tasks. `processOne` has a `defer` rescue
  that forces any item still in `.processing` after the function returns to
  `.failed` with a self-explanatory note — the queue never gets visually
  stuck.
- Unsupported containers (FLAC / WAV / OGG) are intentionally `SKIPPED`, not
  `FAILED`; the metadata suggestion is still surfaced in the row's detail
  line for reference.
