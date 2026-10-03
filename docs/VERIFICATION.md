# Verification record: v1.0.0

Review date: **2026-10-03**. This record distinguishes generated-fixture tests,
native decoder execution, payload checks, antivirus observations, and gameplay.
It is not a malware-free certification or a claim that every game scene works.

## Trusted artifact inputs

- Both supplied `.vcdiff` payloads retain their original SHA-256 values and sizes.
  Exact values and attribution limitations are in [PROVENANCE.txt](../PROVENANCE.txt).
- The distributed Xdelta 3.2.0 Windows x64 ZIP was downloaded from the official
  upstream release and matched the current GitHub release API asset digest:
  `8aca331c3d49ec4465ee8f3f7e3afb92e06d36e32fdec422c3252aaa813a7d2a`.
- Its full `xdelta3.exe` is 336,896 bytes, with SHA-256
  `6e812b38484d0c764291779fadee83ffbe2eceaccb4e3a21f8a043a02654a01e`.
  The installer independently verifies the ZIP and this inner executable.
- The included Xdelta license is byte-identical to the license in the reviewed
  official source archive. Original BLAKE3 and XZ/liblzma licensing texts are
  retained under `licenses/`, with versioned source links in third-party notices.
- Native binary metadata was inspected: AMD64 PE32+, with Windows/VC runtime
  dependencies consistent with the installer's runtime checks. This is a limited
  metadata inspection, not a complete binary or upstream source audit.

## Reproducible automated checks

Verified locally under **Windows PowerShell 5.1.26100.9549**:

| Check | Result and scope |
| --- | --- |
| Installer fixtures plus native DJW roundtrip | **24 passed, 0 failed** using `tests/run-tests.ps1 -NativeDecoder`. |
| Package verifier/builder fixtures | **29 passed, 0 failed** using `tests/package/run-package-tests.ps1`. |
| PowerShell parsing | Installer/module files parsed successfully; final source and CI checks cover the committed scripts. |

The installer suite covers successful staging/backups, genuinely read-only
preflight, modified originals/payloads/ZIP/inner EXE, duplicate decoder entries,
existing backup/pending preservation, native failures, incorrect output size,
second-replacement rollback, failure after backup creation, absent-active restore,
corrupt-backup refusal before any restore, partial restore/rerun, operation locking,
quoted paths with spaces, cancellation, and `XDELTA` environment isolation.

Default cases use generated small files and replace the native decode boundary
with a test double. The opt-in native case executes the pinned official decoder,
confirms actual DJW-compressed window data, and compares source/target SHA-256
after encoding and decoding. It does not use real game files.

Package tests cover known hashes, same-length corruption, missing files, malformed
manifests, absolute/traversal/alternate-stream/device paths, duplicates, junctions,
excluded local data, ZIP contents/checksums, and explicit overwrite controls.
The release builder verifies extracted bytes and never executes extracted scripts.

## Real game data

Both real original backup archives passed the original MD5 compatibility gates.
The pinned official decoder then applied each real supplied patch to a **separate
output under the local workspace**, using the production native decoding wrapper.
The active game installation and its backups were not replaced.

| Decoded file | Verified output bytes | Observed output SHA-256 |
| --- | ---: | --- |
| `FFX_Data.vbf` | 20,799,140,005 | `bc342b69f931d7bf8b613b254210629b79d02cd08c3dc22263249578c9f9b755` |
| `metamenu.vbf` | 21,768,300 | `345caba5e1912851781ac79da331f3daa837d95a1a165e9d84c372f72e296438` |

Both native processes exited successfully and their decoded sizes matched the
production definitions. Independent VCDIFF structure inspection found 2,480 FFX
windows and 3 menu windows, all carrying Adler-32 checksums, with DJW secondary
compression selected. This exercises the actual large-file decoding path.

These whole-output SHA-256 values are **locally observed reference results**, not
independent translation-author signatures. The installer checks native window
checksums and output length, and logs whole-output SHA-256 for reference; it does
not compare that digest against a separately supplied authoritative target hash.

The freshly decoded menu matched the pre-existing installed menu byte-for-byte.
The pre-existing installed FFX archive had a different size and SHA-256. Its
reported gameplay success cannot validate this exact freshly decoded FFX output.
No assertion is made that the different archive is corrupt or incompatible;
binary/content equivalence and gameplay of the new output were not established.

## Antivirus observation

Microsoft Defender custom scans of the project inputs and exact current official
Xdelta ZIP completed with **no threats found**. The scan used `-ScanType 3` and
`-DisableRemediation`: archive contents are scanned, configured file exclusions
are ignored, and the scan does not remediate/delete files.

- Defender platform: **4.18.26080.4**.
- Engine reported by the signature updater: **1.1.26080.3**.
- Preliminary antivirus signatures: **1.459.506.0**. A standard signature update
  completed, after which the local service reported **1.459.523.0**. The extracted,
  hash-verified full decoder was scanned again with no threats found.

Windows Authenticode reports the bundled full decoder as **NotSigned**. Its trust
reference in this package is the pinned official upstream artifact, not a digital
publisher signature.

The built user release ZIP also completed a custom scan with **no threats found**
under signatures **1.459.523.0**. The final archive is checked again after the
verification record and its manifest are finalized. Results are limited to this scanner, these definitions, the bytes
checked, and the review date. No multi-engine consensus, digital code-signing
assurance, or guarantee against future detections is claimed.

## Privacy and publication boundaries

A scan of reviewable project files found no private-key blocks, common GitHub/AWS/
Telegram credential patterns, or personal Windows user-profile paths. Manual
review supplements this bounded pattern scan; it is not a proof that every
possible secret format can be detected.

Only the explicit runtime allowlist and its checksum manifest enter the user ZIP.
The Git repository additionally contains necessary tests, packaging tools, CI,
and maintainer documentation. Local preparation, game files, original backups,
test output, raw diagnostic logs, and generated release archives are excluded
from version control. Public Git identity uses the maintainer's existing GitHub
handle and its noreply address.

## Limits

- This release has not received a complete gameplay playthrough or independent
  translation-quality review. Successful decoding does not prove every scene,
  font, save, game mode, or mod combination works.
- No original translation installer was independently re-extracted for this
  release, and no separate payload redistribution license was supplied.
- Linux, Steam Deck/Proton, macOS, Windows ARM, console editions, and all possible
  Windows/filesystem configurations have not been validated.
- Power-loss recovery cannot be exhaustively simulated by process-level fixture
  tests. The documented original backups remain essential.
- Hash manifests provide integrity relative to a trusted reference, not publisher
  authenticity. Keep antivirus enabled and stop on a detection.

Reproduction commands and release gates are in [the maintainer guide](https://github.com/deymon28/FFX-trans/blob/main/docs/MAINTAINING.md).
Public CI results appear on the repository's
[Actions page](https://github.com/deymon28/FFX-trans/actions).
