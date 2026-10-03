# FFX-trans

An offline Windows installer for the **AlchemistLab Russian text translation of
Final Fantasy X HD Remaster**. It applies the supplied translation patches with
a pinned official Xdelta decoder and keeps verified backups for restoration.

**[Download the latest release](https://github.com/deymon28/FFX-trans/releases/latest)** ·
[Report a problem](https://github.com/deymon28/FFX-trans/issues)

> [!WARNING]
> - This is an unofficial fan translation for **FFX on Windows**, including the
>   game selection menu. **It does not translate FFX-2.** A legitimate copy of the
>   game is required; no original game archives are distributed here.
> - Close the game and launcher. Keep about **20 GiB free on the game drive** and
>   preserve both `.alchemistlab_original` backup files after installation.
> - Only the exact original files listed below are supported. Do not bypass hash
>   checks or install over other modifications to the same archives.
> - Native decoding and recovery are tested, but the newly decoded release output
>   has not been launched or played through during this release review.
> - The bundled official Xdelta ZIP **contains executable files**. PowerShell
>   scripts are executable code too. Antivirus results and matching hashes are
>   evidence, not a guarantee that software is harmless. **Do not disable your
>   antivirus or add exclusions to make installation work.**
> - The MIT license covers this project's own installer code and documentation;
>   it does not relicense the translation, Xdelta, or the game. See
>   [credits and licenses](#credits-and-licenses).

## What you get

The package contains two translation deltas, readable installer scripts, the
official Xdelta 3.2.0 Windows x64 archive, licenses, and an integrity manifest.
There is no download step during installation, telemetry, account requirement,
registry modification, or background service. The scripts operate on the two
game archives, adjacent backup/temporary files, and a temporary decoder folder.

The original `FFXRUS_PC.exe` installer and legacy Xdelta 3.0.4 are not included.
You do not need to find, extract, or replace `xdelta3.exe` yourself.

## Quick start

1. Open [Releases](https://github.com/deymon28/FFX-trans/releases/latest) and
   download **`FFX-trans-v1.0.0.zip`** from **Assets**. Extract the whole ZIP to a
   separate folder such as `C:\Games\FFX-trans`. Do not run files inside the
   archive viewer, and keep all package files together. GitHub's **Code > Download
   ZIP** also contains the required files, plus maintainer material.
2. In Steam, open the game's **Properties > Installed Files > Browse**. Copy the
   game folder path. You can also provide its `data` subfolder.
3. Set the game's text language to **English** in Steam/the original launcher,
   then close the game and launcher.
4. Double-click **`check_install.cmd`**, paste the path, and wait for
   **`Preflight passed`**. This reads files and hashes; it neither runs Xdelta nor
   changes the game. It does not prove write access or successful installation.
5. Double-click **`install_ru.cmd`** and provide the same path. Wait for
   **`Installation completed`**. Large-file hashing and decoding may take several
   minutes or longer on slow drives; leave the window open and keep the computer
   powered on. A full read of the approximately 20 GiB archive is required at
   several stages.
6. Launch through Steam/the original launcher with **English text selected**.
   Check Russian text and fonts in the game. Keep the original backups until
   you are ready to remove the translation.

If any step fails, read [troubleshooting](#troubleshooting). A successful preflight
is not an installation. A successful installation is not a complete gameplay test.

## Requirements and compatibility

| Requirement | Details |
| --- | --- |
| Operating system | 64-bit Windows and 64-bit Windows PowerShell 5.1. The `.cmd` launchers use the system PowerShell. |
| Game | Steam PC edition of **Final Fantasy X/X-2 HD Remaster**, with the exact unmodified FFX and menu archives below. |
| Runtime | Microsoft Visual C++ x64 runtime and UCRT. If missing, use [Microsoft's download page](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist) or its [official x64 installer](https://aka.ms/vc14/vc_redist.x64.exe). This project does not install it for you. |
| Filesystem | Local NTFS or ReFS for adjacent atomic file replacement. Network shares, directory junctions, and symbolic links are rejected. |
| Free space | About 20 GiB **in addition to the installed game** on the game volume. The installer prints its exact minimum. Allow a few MiB in `%TEMP%` for the decoder. |
| Permissions | Write access to the game data folder for installation/restoration. Start normally; elevated privileges are not a default requirement. |
| Paths | Prefer short paths containing characters supported by the Windows system code page. Spaces are supported. The native decoder may not support every Unicode or long path. |

Linux, macOS, Steam Deck/Proton, Windows ARM, console editions, and other mods
that change these same archives are outside the tested support scope. Historic
guides for other installers do not establish compatibility for these scripts.
No claim is made about every scene, font, save, or optional game mode.

### Supported originals

The installer checks these MD5 values to identify the exact game data revision.
MD5 is used for compatibility with the supplied patch metadata, not as a
cryptographic authenticity guarantee. Distributed patch/decoder checks use SHA-256.

| File inside `data` | Required original MD5 |
| --- | --- |
| `FFX_Data.vbf` | `DBB4ADAF14FBC80D631266A876D00892` |
| `metamenu.vbf` | `535BBD83176480ABCA1D1AAF33DF0091` |

Steam's file verification can restore clean game data, but it can also remove
other archive modifications. Preserve any mod-specific backups before using it.

## Verify the downloaded package

From a PowerShell window opened in the extracted package, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify_package.ps1
```

This reads `SHA256SUMS.txt` and verifies every listed file without running Xdelta
or accessing the game. A missing or altered file is a failure. The manifest is
an integrity check, **not a digital signature**: obtain the archive and published
checksum from a source you trust. The verifier itself is readable PowerShell.

To compare a release ZIP with its separately published `.sha256` file:

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath .\FFX-trans-v1.0.0.zip
```

The `.cmd` files use `-ExecutionPolicy Bypass` for that PowerShell process only;
they do not change the machine's persistent policy. If organizational policy or
security software blocks execution, consult its administrator or review the
reported detection; do not weaken protections to proceed.

## What installation changes

1. Resolve the game data folder and reject unsupported links/network paths.
2. Check that the game and launcher are stopped, and take an exclusive operation
   lock for installation.
3. Check runtime availability, SHA-256 of both patch files, the official ZIP,
   and its full `xdelta3.exe`; verify both original game MD5 values and free space.
4. Extract only the pinned full decoder to a unique `%TEMP%\ffx-trans-*` folder.
   The decoder's file handle remains locked while it is in use.
5. Build **both** translated archives next to the originals as
   `.alchemistlab_pending` files. Original game files remain in place during
   decoding. Xdelta checks VCDIFF window checksums.
6. Check output lengths and print output SHA-256 values for reference, recheck
   originals and running processes, and replace each archive atomically while
   preserving its original. There is no independently supplied whole-output hash
   in the translation metadata; the displayed digest is not a separate hash gate.
7. Remove owned temporary outputs and the temporary decoder. The operation lock
   is released when the script exits. Originals remain in the two backup files.

| Path relative to the game folder | Purpose |
| --- | --- |
| `data\FFX_Data.vbf` | Active FFX archive, replaced on success. |
| `data\metamenu.vbf` | Active selection-menu archive, replaced on success. |
| `data\FFX_Data.vbf.alchemistlab_original` | Original FFX archive; keep it. |
| `data\metamenu.vbf.alchemistlab_original` | Original menu archive; keep it. |
| `data\*.alchemistlab_pending` | Temporary outputs; an interrupted run may leave them behind. |
| `data\.alchemistlab.lock` | Exclusive operation lock; normally disappears on exit. |

Replacement is atomic **per file**. The pair is not a single filesystem
transaction. A handled error triggers rollback; power loss or forced termination
can leave a mixed state that needs the restore tool. Save files and `FFX2_Data.vbf`
are not installation targets. Make your usual save backup separately.

## Remove the translation or recover after interruption

1. Close the game and launcher.
2. Run **`restore_original.cmd`** and enter the game folder or `data` folder.
3. The tool validates the available originals before restoring anything.
4. Type **`RESTORE`** exactly when prompted. Any other answer cancels.
5. Wait for **`Both original files are restored and verified`**.

Restoration does not need Xdelta or the translation payloads. It can handle a
missing active file, a leftover temporary output, or one archive already restored
by an earlier interrupted recovery. A successful restore consumes the original
backup files by putting them back in their active locations.

If restoration fails, **preserve all active files and `.alchemistlab_original`
backups**, resolve the reported problem, and rerun the restore tool. Do not delete
backups or rename files at random. If the original backups are lost or invalid,
Steam verification is an alternative way to retrieve game files; it may replace
other mods as well. Restore clean originals before reinstalling or updating this
translation package.

## Command-line use

For predictable exit codes without the `.cmd` launchers' final pause, use the
PowerShell entry points. Replace the example path with your own game directory:

```powershell
# Read-only game preflight; does not execute the decoder.
powershell -NoProfile -ExecutionPolicy Bypass -File .\install_ru.ps1 -GameDir "D:\SteamLibrary\steamapps\common\FINAL FANTASY FFX&FFX-2 HD Remaster" -CheckOnly

# Install.
powershell -NoProfile -ExecutionPolicy Bypass -File .\install_ru.ps1 -GameDir "D:\SteamLibrary\steamapps\common\FINAL FANTASY FFX&FFX-2 HD Remaster"

# Restore; still asks for RESTORE confirmation.
powershell -NoProfile -ExecutionPolicy Bypass -File .\restore_original.ps1 -GameDir "D:\SteamLibrary\steamapps\common\FINAL FANTASY FFX&FFX-2 HD Remaster"
```

If `-GameDir` is omitted, the script prompts for it. Install/check/restore errors
return exit code `1`; successful completion returns `0`. A cancelled restore also
returns `0`, so read its `Cancelled` message when running interactively.

## Troubleshooting

| Message or symptom | What to do |
| --- | --- |
| `Original MD5 mismatch` | Wrong game revision, an existing translation, or another archive mod. Restore clean originals; never change the expected hash to force acceptance. |
| `Existing backup or temporary output` | Run `restore_original.cmd` first, then retry installation. Keep the backups. |
| `Patch SHA-256 mismatch`, `Xdelta ZIP SHA-256 mismatch`, or executable mismatch | Stop and extract a fresh copy of this project's release into a new folder. Do not substitute another decoder, even one with the same version label. |
| `Insufficient free space` | Free space on the **game volume**. Original data stays present while both outputs are built. |
| `Microsoft Visual C++ x64 runtime is missing` | Install the x64 runtime from the Microsoft link above. The old installer's x86 2010 instructions do not apply here. |
| `Close the game and its launcher` | Exit both before retrying; do not start them during installation or restoration. |
| `Cannot lock the game folder` / access denied | Close another running patch operation and check folder permissions. Do not delete locks while another operation is running. |
| Directory links or network shares rejected | Use the real directory on a supported local NTFS/ReFS volume. |
| Xdelta cannot start / DLL error | Check runtime availability, antivirus messages, and path compatibility. Keep the full error and exit code. |
| `Decoded size mismatch`, or an output hash differs from the verification record | Stop; preserve originals. Report the package version, error, and expected/actual hashes without uploading game archives. |
| Antivirus or SmartScreen warning | Stop and record the detection and file SHA-256. Do not disable protection or assume it is a false positive. See [SECURITY.md](SECURITY.md). |
| Installation appears idle | Large-file hashing/decoding can take minutes, especially on HDDs. Keep the console open and check disk activity; do not launch the game in parallel. |
| Text is still English / fonts look wrong | Check English text selection and that you patched the installation you are launching. Report the exact place and package version; do not assume every gameplay scene has been verified. |
| `Recovery is incomplete` | Preserve active archives and all backups; resolve the error and rerun `restore_original.cmd`. |

For support, open an [issue](https://github.com/deymon28/FFX-trans/issues) with the
package version, Windows/PowerShell versions, stage, complete **redacted** error,
and relevant hashes. Remove usernames, personal paths, account IDs, and secrets.
Do not upload game archives, saves, credentials, or unrelated logs.

## Verification and limitations

See the dated [verification record](docs/VERIFICATION.md) for antivirus results,
real decoder checks, fixture recovery tests, and the limits of game verification.
[PROVENANCE.txt](PROVENANCE.txt) records exact upstream assets and payload hashes.
Tests do not establish translation accuracy or certify malware absence.

## Credits and licenses

| Component | Credit and terms |
| --- | --- |
| Russian translation payloads | **[AlchemistLab](https://vk.com/club108745115)**. The supplied patches are retained byte-for-byte. The [historic Steam guide by felbelov](https://steamcommunity.com/sharedfiles/filedetails/?id=3173872912) also credits the team. It is an attribution reference, not installation guidance for this package. |
| Delta codec | **[Joshua MacDonald and Xdelta contributors](https://github.com/jmacd/xdelta)**; [official 3.2.0 release](https://github.com/jmacd/xdelta/releases/tag/v3.2.0), [documentation](https://jmacd.github.io/xdelta/), and [source archive](https://github.com/jmacd/xdelta/releases/download/v3.2.0/xdelta3-3.2.0.tar.gz). Distributed under [Apache-2.0](XDELTA_LICENSE.txt). |
| Libraries bundled by Xdelta | **[BLAKE3 team](https://github.com/BLAKE3-team/BLAKE3)** and **[XZ/liblzma contributors](https://tukaani.org/xz/)**. Their licenses and component details are included in [third-party notices](THIRD_PARTY_NOTICES.md#libraries-statically-linked-by-upstream-xdelta). |
| Game | **Square Enix** and the game's credited creators. [Official Steam page](https://store.steampowered.com/app/359870/). This project is not affiliated with or endorsed by Square Enix, Steam, AlchemistLab, or Xdelta. |
| Installer and packaging | Maintained by **[deymon28](https://github.com/deymon28)**. Project-authored scripts, tests, and documentation are licensed under [MIT](LICENSE). |

The translation payloads were supplied without a separate redistribution license
document. This repository does not claim ownership of them or grant additional
rights to the translation or game. See [third-party notices](THIRD_PARTY_NOTICES.md)
for the component boundaries and provenance limitations.

## For maintainers

Read [MAINTAINING.md](https://github.com/deymon28/FFX-trans/blob/main/docs/MAINTAINING.md) for architecture, fixture/native tests,
manifest updates, release building, and publication checks. Runtime releases use
an explicit file allowlist so local game data, logs, test outputs, and credentials
cannot be included merely because they exist in the working folder.
