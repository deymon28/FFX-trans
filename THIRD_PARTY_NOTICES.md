# Third-party notices

The root [MIT license](LICENSE) applies to project-authored installer scripts,
tests, packaging tools, and documentation. It does not apply to the components
listed below or override their owners' rights.

## AlchemistLab translation

- Files: `FFX Patch.vcdiff` and `metamenu patch.vcdiff`.
- Credited translation team: [AlchemistLab](https://vk.com/club108745115).
- Attribution reference: [felbelov's historic Steam guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3173872912).
- Both payloads were supplied to this project and retained byte-for-byte.
  [PROVENANCE.txt](PROVENANCE.txt) identifies them by SHA-256.
- The original installer was not independently re-extracted during this release
  preparation. Its exact translation revision and full individual contributor
  list have not been independently established.
- No separate translation redistribution license accompanied the supplied
  payloads. They are not relicensed under MIT or Apache-2.0, and no additional
  rights to the translation or game are granted by this repository.

## Xdelta 3.2.0

- Copyright 2016 Joshua MacDonald, with contributions from
  [Xdelta contributors](https://github.com/jmacd/xdelta/graphs/contributors).
- Project: <https://github.com/jmacd/xdelta>.
- Release: <https://github.com/jmacd/xdelta/releases/tag/v3.2.0>.
- License: Apache License 2.0; the unmodified license text is included in
  [XDELTA_LICENSE.txt](XDELTA_LICENSE.txt).
- The Windows x64 release archive is distributed unmodified, including its
  upstream README. Only its full `xdelta3.exe` is extracted and executed by the
  installer. The contained minimal `xdelta3decode.exe` is not used.
- [Corresponding source release](https://github.com/jmacd/xdelta/releases/download/v3.2.0/xdelta3-3.2.0.tar.gz)
  is linked rather than duplicated in the runtime package. No changes have been
  made to upstream decoder binary or source code.
- Exact release-asset and executable digests are recorded in PROVENANCE.txt.
  Pinning bytes matters: a release asset can be replaced under the same filename.

## Libraries statically linked by upstream Xdelta

The official Xdelta archive's README identifies statically linked BLAKE3 and
liblzma. The corresponding reviewed 3.2.0 source archive sets BLAKE3 `1.8.5` and
XZ/liblzma `v5.8.3` as its dependency defaults. These libraries are included by
the upstream binary build; this project neither rebuilds nor changes them.

- **BLAKE3**: [BLAKE3 team](https://github.com/BLAKE3-team/BLAKE3/tree/1.8.5),
  including Jack O'Connor and Samuel Neves. The Apache-2.0 option and original
  copyright notice are preserved in [BLAKE3_Apache-2.0.txt](licenses/BLAKE3_Apache-2.0.txt),
  copied from the [versioned upstream license](https://github.com/BLAKE3-team/BLAKE3/blob/1.8.5/LICENSE_A2).
- **liblzma**: [Tukaani XZ contributors](https://tukaani.org/xz/),
  [versioned source](https://github.com/tukaani-project/xz/tree/v5.8.3).
  The upstream licensing overview is retained in [XZ_COPYING.txt](licenses/XZ_COPYING.txt)
  and its Zero-Clause BSD license in [XZ_0BSD.txt](licenses/XZ_0BSD.txt).
  This package does not redistribute the separate XZ command-line tools.

## Final Fantasy X/X-2 HD Remaster

The game and associated names, artwork, text, and trademarks belong to their
respective rights holders, including Square Enix. Obtain the game separately
from an authorized source such as its [Steam store page](https://store.steampowered.com/app/359870/).
Original game archives, saves, and game executables are not included in this
project. This is an unofficial fan project without claimed endorsement.
