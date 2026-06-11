# Linux Parity & VM Validation Session Journal

Started: 2026-06-11 (autonomous session). Mission: bring portable/linux GTK port
to parity with portable/mac (journal items 52-69), then install and validate in
the Parallels Ubuntu 24.04 ARM VM with captures. Evidence and decisions land here.

## Timeline
- [open] Journal created. Mission brief produced by rephrase agent (Objectives:
  1 journal, 2 code-inspection parity + implementation, 3 verify computer
  control before GUI work, 4 install in VM, 5 test+capture parity verdict).
- [open] Parallels reported downloading Ubuntu 24.04 ARM. Parity audit fanned
  out first; VM work follows once image lands.
- [audit] Parity matrix delivered. Key gaps: per-task spdf_open/close in render
  worker (kills any list cache), sync main-thread renders on every page jump,
  no display-list/_opts adoption, no render tokens, no byte cap, no wheel/pinch
  zoom at all, per-scroll-tick sync save_session, minimap placeholders only,
  OCR list 5 vs 19. Linux builds on the Mac host (gtk+3 3.24.52) - local
  compile gates possible. VM "Ubuntu 24.04 (with Rosetta)" running.
- [plan] Wave 1: Agent A (worker docs + async nav renders + list cache + tokens
  + byte cap) in /tmp/spdf-lxA; Agent D (OCR languages + small parity) in
  /tmp/spdf-lxD; VM prep agent. Wave 2 after A: B (anchored zoom), C (scroll
  coalescing + minimap thumbnails). Then VM build + capture matrix.
- [wave1] Agent D done (+108 lines, builds): OCR 5->19 languages; NEW copy-
  selected-text path (Ctrl+C, context menu, Edit menu) with whitespace-collapse
  toggle persisted as collapseWhitespaceWhenCopyingText; startup save batching.
  Patch held at /tmp/lxD.patch pending merge after Agent A.
- [wave1] Agent A merged (+288/-60): persistent worker docs, async nav renders,
  list-cache adoption, render tokens, 96MB cap. Agent D merged (+108).
  Linux builds clean on Mac host after both.
- [wave2] Agents B (anchored Ctrl+wheel/pinch zoom) and C (scroll coalescing +
  minimap thumbnails) launched in /tmp/spdf-lxB, /tmp/spdf-lxC.
- [vm] Prep complete: exec=root, gtk 3.24.41, gcc 13.2, repo rsynced to
  /root/shenzhen-pdf, mupdf ARM build running (/root/mupdf-build.log,
  ~15-30min). GDM login pending for GUI tests (autologin plan: gdm3
  custom.conf + reboot). Screenshot /tmp/vm_ready.png.
