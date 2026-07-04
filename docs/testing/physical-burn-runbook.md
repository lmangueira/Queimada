# Physical Burn Runbook (U10)

Manual validation of everything the mocked CI tests cannot cover: real burns
on real media. Hardware: the owner's DVD burner and Blu-ray burner (the BD
drive also reads/writes CD and DVD).

**Prerequisite:** run the U1 spike first (`Spike/README.md`) — its GO/NO-GO
decides which build variant you validate here (`app-mas` on GO, `app-direct`
otherwise).

Build the app: `./Packaging/scripts/make-app.sh app-direct` (or `app-mas`),
then `open "dist/Blu-Ray Burner.app"`.

## Pass criteria used below

- **XPLAT**: disc mounts and every file reads **byte-identical** on macOS,
  Windows, and Linux (compare with `shasum -a 256` / `sha256sum` /
  `CertUtil -hashfile`). Linux/Windows machine or VM needed once per row.
- **VERIFY**: in-app verify pass completes and reports success.

## Test matrix

| # | Media | Action | Pass criterion | Result / date |
|---|-------|--------|----------------|---------------|
| 1 | CD-R | Burn a folder tree (nested folders, files with spaces/accents in names) | VERIFY + XPLAT; **ISO 9660/Joliet bridge**: disc readable on a system without UDF (or check `isoinfo -d`) | |
| 2 | DVD±R | Burn a mixed set (~4 GB) | VERIFY + XPLAT (UDF) | |
| 3 | BD-R | Burn ~20 GB including **one file > 4 GB** | VERIFY + XPLAT; the >4 GB file byte-identical (R5) | |
| 4 | BD-R DL | Burn > 25 GB set | Capacity detected ~50 GB (R12/assumption); VERIFY | |
| 5 | Any | Assemble set larger than the disc | Burn button disabled, overage shown (R12/AE3) | |
| 6 | Any writable | Start a burn, press **Cancel Burn** mid-write | App reports "Burn cancelled"; next blank disc burns fine | |
| 7 | Any | Deliberately unreadable source (delete a file after adding it), verify ON | Burn/verify reports FAILURE, never success (R9/AE2) | |
| 8 | CD-RW | Quick erase, then reburn | Erase completes; disc accepts new burn | |
| 9 | DVD-RW or BD-RE | **Complete** erase | Erase completes (slower); disc blank | |
| 10 | Any | Burn a small `.iso` image (e.g. a Linux netinst) | Disc matches image (`diff <(dd if=/dev/rdiskN) image.iso` or boot test) | |
| 11 | BD-R | Eject/insert media repeatedly with app open | Status bar tracks media within ~2 s (U3 polling) | |

## Defect log

| Date | Row | Observed | Notes |
|------|-----|----------|-------|
| | | | |
