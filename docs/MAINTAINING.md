# Maintainer guide

## Scope and architecture

The project distributes existing translation deltas and a small Windows wrapper.
Do not change translation payload bytes, patch format, compatible original hashes,
or recovery naming as part of unrelated cleanup.

| File | Responsibility |
| --- | --- |
| `check_install.cmd` | Interactive read-only preflight through `install_ru.ps1 -CheckOnly`. |
| `install_ru.cmd`, `install_ru.ps1` | User entry point, optional game path prompt, exit status. |
| `restore_original.cmd`, `restore_original.ps1` | User entry point for verified restoration. |
| `patch_core.psm1` | File definitions, validation, locking, staging, replacement, rollback, and restore. Exports only `Invoke-RuInstall` and `Invoke-RuRestore`. |
| `decoder.ps1` | Pinned archive/EXE integrity, safe extraction, runtime checks, temporary decoder lifetime, native process boundary. Loaded by the module. |
| `verify_package.ps1` | Read-only SHA-256 manifest verification, including safe relative-path validation. |
| [`tests/run-tests.ps1`](https://github.com/deymon28/FFX-trans/blob/main/tests/run-tests.ps1) | Generated filesystem fixtures and optional native DJW roundtrip. |
| [`tools/package-files.txt`](https://github.com/deymon28/FFX-trans/blob/main/tools/package-files.txt) | Exact allowlist for the user release ZIP and manifest. |
| [`tools/update-manifest.ps1`](https://github.com/deymon28/FFX-trans/blob/main/tools/update-manifest.ps1) | Update or check hashes for reviewed allowlisted files. |
| [`tools/build-release.ps1`](https://github.com/deymon28/FFX-trans/blob/main/tools/build-release.ps1) | Build and verify an allowlisted release ZIP and its checksum. |

The runtime package deliberately omits development tests, Git metadata, CI
configuration, and tooling. Clone the repository or use **Code > Download ZIP**
when working on the project. There are no Python, Node, or Pester dependencies
for normal operation, tests, or packaging.

## Safety invariants

- Verify both originals and all distributed executable/payload bytes before
  invoking the decoder. Hash checks must fail closed.
- Build both pending outputs before replacing either original. Backups are
  created by adjacent per-file atomic replacement, never by early renaming.
- Recovery must validate all available originals before its first replacement.
  It must remain usable after a partial restore and when one active file is absent.
- Preserve the original files and diagnostics after incomplete recovery. Do not
  delete arbitrary paths or accept external output locations in fixture tests.
- Reject links/junctions and unsupported volumes; keep the exclusive game-folder
  operation lock. A preflight is read-only and does not invoke the decoder.
- The decoder ZIP and inner EXE are verified separately. Extract only the expected
  entry to a fixed filename; do not use generic archive extraction for execution.
- Keep scripts compatible with **Windows PowerShell 5.1**, including the
  `[NullString]::Value` workaround for `File.Replace` without a backup path.
- Do not silently weaken checks to accommodate a different game revision,
  unsigned/tampered download, antivirus detection, or filesystem limitation.
- Do not test against the user's live game installation. Real payload decoding
  requires a separate output location and verified original files; record it
  separately from unit/fixture tests and in-game validation.

## Run the checks

Run these from the repository root on Windows x64 with the documented VC runtime:

```powershell
# No native decoder execution: integrity, staged install, and recovery fixtures.
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1

# Explicitly execute the pinned decoder on generated source/target data.
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1 -NativeDecoder

# Verifier and release-builder edge cases, using generated package fixtures.
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\package\run-package-tests.ps1

# Confirm the reviewed package's bytes and that its manifest is current.
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify_package.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-manifest.ps1 -Check

git diff --check
```

Default installer tests use small generated files under `.local/test-run-*` and
replace the native decoding boundary with a test double. They exercise actual
filesystem backup/replacement/restore logic and real archive/EXE integrity checks.
Fault injection covers failed decoding and replacement/recovery interruption.
The opt-in native case performs real DJW compression and decoding and compares
source/target SHA-256. It does not install into a real game or test gameplay.

The package-tooling tests live under
[`tests/package`](https://github.com/deymon28/FFX-trans/tree/main/tests/package)
and cover malformed/unsafe manifests, modified or missing files, unlisted data,
archive contents, and refusing an accidental overwrite of an existing release.
Fixtures must remain below project `.local`; cleanup must validate final absolute
paths and refuse links before recursive removal.

CI uses a pinned `actions/checkout` commit, Windows PowerShell, and read-only
repository permissions. It runs generated fixture/native checks and package
verification; it has no original game files or release-upload credentials.

## Update trusted inputs and the manifest

1. Inspect the source change, license, provenance, and any decoder compatibility
   impact first. A matching filename/version label is insufficient for an asset.
2. For Xdelta, compare the actual download SHA-256 with the current GitHub release
   API asset digest. Inspect archive entries, inner EXE size/hash, and upstream
   license; scan before native execution. Update the explicit constants only
   after this review. Do not fetch arbitrary decoder versions during installation.
3. Update README, third-party notices, PROVENANCE, and the
   dated verification record where their claims are affected.
4. Review `tools/package-files.txt`. Every entry must be necessary runtime data,
   user documentation, a notice/license, or the verifier. Do not add `.local`,
   real game files, developer logs, environments, caches, or generated releases.
5. Regenerate the manifest after the final content changes:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-manifest.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\verify_package.ps1
   ```

The manifest covers the runtime allowlist, not every developer file in the Git
repository. It excludes itself. Avoid changing line endings after hashing:
project text is LF, `.cmd` files retain their CRLF bytes, and the unmodified
upstream license and binary assets are preserved by `.gitattributes`.

## Build a user release

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-release.ps1 -Version 1.0.0
```

Outputs are `dist/FFX-trans-v1.0.0.zip` and
`dist/FFX-trans-v1.0.0.zip.sha256`. Existing outputs are refused unless `-Force`
is explicitly supplied. `dist` is ignored by Git.

The builder requires the manifest and allowlist paths to match exactly. It writes
only those files plus `SHA256SUMS.txt`, uses a fixed ZIP timestamp rather than
local file timestamps, and verifies extracted bytes using trusted source helper
functions. It never executes scripts from the extracted ZIP. Unlisted local
files cannot be swept into the release by recursive directory packaging.

## Publication checklist

- Run the relevant tests, manifest verification, and release builder successfully.
- Scan the exact release archive and executable with current available antivirus
  signatures. Record scanner/version/date/result and limitations; never describe
  one clean scan as proof of universal malware absence.
- Inspect the staged paths and diff, including `.github`, documentation, licenses,
  and binary names. Confirm no game archives/backups, credentials, machine paths,
  personal identifiers, debug files, or local preparation entered the commit.
- Use a public handle and GitHub noreply commit email. Rewrite published history
  only with explicit maintainer authorization, a private recovery copy, and
  checked remote references. Update affected tags and release assets as well.
- Publish only with authorization. Upload the reviewed user ZIP and its separate
  SHA-256 file to a versioned GitHub Release targeting the verified commit.
- Verify the remote commit, CI result, published asset metadata, and downloaded
  release bytes. Check README rendering, relative links, credits, download links,
  and prominent warnings from the published page.
- Keep local original preparation copies and real-game test outputs private.
  Remove only task-owned reproducible scratch data when it is no longer needed.

Do not put credentials, unredacted console logs, machine/account data, or user game
paths in public verification records. A useful record states what was tested,
which exact artifacts were checked, what passed, and what remains unverified.
