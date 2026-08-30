# Bring the guest-rendered PNG back to the Mac as base64 on stdout.
#
# WHY NOT JUST COPY IT TO THE SHARE. That is what this used to do, and it broke:
# sync-to-vm.sh runs rsync with --delete-excluded, so the staging tree's
# portable/win/build/ directory -- the obvious drop box -- is deleted on every
# sync, including the one vm-build.sh performs moments before the probe runs.
# Any transport that depends on the staging tree depends on another track's
# rsync flags, and will break again the next time those change.
#
# stdout has no such coupling. A page render is tens of kilobytes, base64 is
# about a third larger, and prlctl carries it fine.
#
# Emitted in fixed-width chunks rather than as one enormous line so nothing in
# the console/pipe path is tempted to wrap it at a width we did not choose; the
# Mac side strips all whitespace before decoding, so the chunking is invisible.
$ErrorActionPreference = 'Stop'

$src = 'C:\spdf-build\probe-page.png'
if (-not (Test-Path $src)) {
    [Console]::Error.WriteLine("fetch_probe_png: missing $src")
    exit 1
}
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($src))
for ($i = 0; $i -lt $b64.Length; $i += 76) {
    $n = [Math]::Min(76, $b64.Length - $i)
    [Console]::Out.WriteLine($b64.Substring($i, $n))
}
exit 0
