Android native dependency notices for DiffUpdater core 2.0.0

Dependency: com.github.Chiu-xaH.DiffUpdater:core:2.0.0
Upstream: https://github.com/Chiu-xaH/DiffUpdater/tree/2.0.0/core

The AAR packages HPatch plus bsdiff/bspatch native libraries. MyCHU invokes only
HPatch with zlib HDiff patches. Notices for bundled native components are kept
here even when MyCHU does not select their compression or patch formats.

License sources, retrieved 2026-10-11:
- DiffUpdater: upstream root LICENSE (MIT, Chiu-xaH).
- HDiffPatch: https://github.com/sisong/HDiffPatch/blob/master/LICENSE
  This upstream file also preserves the libdivsufsort notice.
- bsdiff/bspatch: copyright/license headers of the bundled Colin Percival sources.
- bzip2: https://github.com/libarchive/bzip2/blob/bzip2-1.0.6/LICENSE
  and https://github.com/libarchive/bzip2/blob/bzip2-1.0.8/LICENSE
- zlib: https://github.com/madler/zlib/blob/v1.3.1/LICENSE
- Zstandard: https://github.com/facebook/zstd/blob/v1.5.7/LICENSE
- LZMA SDK (Igor Pavlov): https://www.7-zip.org/sdk.html
  LZMA SDK is placed in the public domain.

These notices do not assert that every bundled precompiled HPatch component
uses the listed source release; the AAR does not supply full build provenance.
They preserve the upstream statements for the included native components.
