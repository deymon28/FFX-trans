# Security and privacy

## Before running the installer

Download from this repository's [releases](https://github.com/deymon28/FFX-trans/releases),
verify the published archive checksum, extract the full package, and run
`verify_package.ps1`. Review the readable scripts if you need to assess their
behavior. Hashes detect changes relative to a trusted reference; they are not
signatures and do not prove that a file is safe.

The package contains native executable code inside the official Xdelta ZIP.
The scripts verify the archive and its full decoder before execution, and keep
that decoder locked during use. They perform no network requests, telemetry,
automatic dependency installation, antivirus exclusions, or persistent execution
policy changes. Native decoding disables external compression commands and clears
the `XDELTA` option-injection environment variable for the duration of the call.

Run with ordinary permissions where the game folder permits it. The wrapper is
not intended as a defense against another process already able to modify your
scripts or game folder under the same account. Do not run a changed package just
because its own changed manifest reports a match.

## Antivirus findings

If antivirus or SmartScreen blocks a file, stop. Preserve the detection name,
scanner/signature versions, package version, and relevant SHA-256. Do not disable
protection, add exclusions, or label the finding a false positive without evidence.
The [verification record](docs/VERIFICATION.md) documents one release check; its
result is time-specific, not a guarantee against malware or future detections.
No claim is made that all antivirus engines agree.

## Reporting

For ordinary installer failures, use [GitHub Issues](https://github.com/deymon28/FFX-trans/issues).
For a security issue, use [GitHub's private vulnerability reporting page](https://github.com/deymon28/FFX-trans/security/advisories/new)
if that feature is enabled. Do not put credentials or sensitive exploit details
into a public issue; if private reporting is unavailable, open a minimal issue
requesting a private contact without disclosing those details.

Include the affected version, reproduction steps using synthetic data where
possible, the observed impact, and relevant file hashes. Do not upload original
game files, saves, tokens, or unredacted machine logs.

## Data minimization

Console errors can contain the paths you enter. Remove usernames and personal
directories before posting screenshots or console text. No persistent log file
is produced by the normal installer. Generated test fixtures, local release
preparation, original backups, and release output are ignored by Git and excluded
from the runtime release allowlist.

The public commit identity uses a GitHub handle and GitHub noreply address.
Upstream project credits and the generic drive paths embedded in the supplied
VCDIFF metadata are attribution/build metadata, not local user data.
