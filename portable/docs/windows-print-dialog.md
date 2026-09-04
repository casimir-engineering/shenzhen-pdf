# The Windows print dialog, and why this port has two

`PrintDlgExW` does not return on this machine. That single fact is why File >
Print used to freeze the app, why the port now has a print dialog of its own,
and why there is a watchdog between the two.

This document is the measurement, not a summary of it. Everything below was
produced by `portable/win/tests/print_dialog_probe.c` on **Windows 11 Pro,
build 26200, x64, an unlocked interactive session, 2026-09-04**, with two
healthy printers installed (`Brother DCP-L3550CDW series`, `Microsoft Print to
PDF`; `Spooler` and `PrintWorkflowUserSvc` both Running).

## 1. The narrowest reproduction

```
PrintDlgExW, hwndOwner = a valid visible window   NEVER RETURNS, no window ever appears
PrintDlgExW, hwndOwner = NULL                     returns E_HANDLE (0x80070006) immediately
```

That is the whole bug. It is two lines because both halves matter: with a NULL
owner the call fails instantly and creates nothing, and with a real owner it
wedges forever. `PRINTDLGEX`'s documentation says `hwndOwner` "must be a valid
window handle; it cannot be NULL", and this host enforces that with `E_HANDLE` —
so there is no owner value that works.

Nothing else about printing is broken here. Every other dialog comdlg32 and the
spooler can show, shows:

| Call | Result on this host |
| --- | --- |
| `PrintDlgW`, `PD_RETURNDC \| PD_NOPAGENUMS` | **works** — "Print" appears; OK returns TRUE with a 600 dpi printer DC (4961x7016 device px); Cancel returns FALSE |
| `PrintDlgW`, `PD_RETURNDEFAULT` | **works** — no UI, returns TRUE with the default printer's DEVMODE |
| `PrintDlgW`, `PD_PRINTSETUP` | **works** — "Print Setup" appears |
| `PageSetupDlgW` | **works** — "Page Setup" appears |
| `DocumentPropertiesW`, `DM_IN_PROMPT \| DM_IN_BUFFER \| DM_OUT_BUFFER` | **works** — "Microsoft Print to PDF Document Properties" appears; OK returns `IDOK` with the edited DEVMODE |
| `PrintDlgExW` | **hangs** (or `E_HANDLE`), as above |

**This corrects the earlier finding in this repository.** `spdf_win_print.h`,
`print_e2e_test.c` and `print_math_test.c` all used to say that *no* comdlg32
print dialog could be shown on this machine, and that the classic `PrintDlgW`
"hangs identically". It does not. It opens, it can be dismissed, and it hands
back a working printer DC. Only `PrintDlgExW` is broken.

Reproduce any row with:

```sh
export SPDF_OUT='C:\spdf-build\<yours>' SPDF_MUPDF_LIBDIR='C:\spdf-build\mupdf'
cmd //c "<repo>\portable\win\build-native.cmd" print_dialog_probe portable/win/tests/print_dialog_probe.c
%SPDF_OUT%\print_dialog_probe.exe ex --owner-main --seconds=8      # hangs, exit 11
%SPDF_OUT%\print_dialog_probe.exe classic --drive=ok --seconds=8   # works, exit 0
%SPDF_OUT%\print_dialog_probe.exe docprops --seconds=8             # works, exit 11 (waiting for a human)
```

The probe puts the comdlg32 call on a worker thread and watches this process's
own top-level windows from the main thread, so it separates two things a plain
synchronous call conflates: **did the call return** and **did a window appear**.
Its exit code says which — `0` returned, `10` deadline with no window of ours
(the hang), `11` deadline with a window (an ordinary modal dialog). Always run
it under a timeout: every UI scenario is expected to outlive the deadline, and
the abandoned thread never comes back.

## 2. What was tried, and did not help

The hang is not the app's, and it is not a configuration this port can change.
Each of these was varied on its own, with a valid owner window, and `PrintDlgExW`
hung in every one:

| Variable | Values tried | Effect |
| --- | --- | --- |
| COM apartment of the calling thread | STA, MTA, none | none. (Under MTA an **invisible** `#32770` titled "Print" *is* created and then never shown — the hand-off wedges after the host window exists.) |
| Message pump on the calling thread | pumping, not pumping | none |
| Owner window | on the calling thread, on another thread that keeps pumping, NULL | NULL fails fast; both real owners hang |
| Process DPI awareness | untouched (unaware), system-aware, per-monitor-v2 | none |
| Common Controls 6 activation context | absent (the unmanifested probe), activated via `CreateActCtxW` | none |
| `PD_RETURNDC` | with, without | none |
| Our own property page (the Scaling tab) | with, without | none |

So the **COM apartment at call time — the strongest remaining candidate before
this sweep — is not the cause.** For the record, the app's main thread is an STA
when Print runs: `spdf_win_d2d.cpp` calls
`CoInitializeEx(NULL, COINIT_APARTMENTTHREADED)` during window creation and never
uninitializes it. That is exactly the probe's default (`--com=sta`), which hangs.

The earlier investigation's dump of the wedged process is consistent with all of
this: `windows.internal.shellcommon.PrintExperience.dll` and
`Print.PrintSupport.Source.dll` are loaded, i.e. comdlg32 has handed off to the
Windows 11 print experience and the hand-off does not come back. Nothing an
application does before the call changes that.

**One machine is not every machine.** The app's call is exonerated, so
`PrintDlgExW` stays the primary path: on a host where it works it is the right
dialog, it is the one the reader expects, and it is where our Scaling tab lives.
It is simply no longer allowed to take the process with it.

## 3. The watchdog

`spdf_win_print_system_dialog()` (`spdf_win_print_dialog_system.cpp`):

1. **Refuses a NULL owner immediately**, with a sentence and no thread. Measured:
   that call cannot succeed here, and making the reader wait for it would be four
   seconds spent on a certainty.
2. Puts `PrintDlgExW` on a **dedicated thread** with its own STA and its own
   message pump. Not because either turned out to matter here, but because that
   is how a thread that shows a dialog is written, and this host is not every
   host.
3. **Waits on the calling (UI) thread**, pumping messages and with the parent
   window disabled — modal against the parent only, like every other dialog in
   this port. The owner's thread must stay in the message system or a
   cross-thread `SendMessage` from the print experience would deadlock it.
4. **Watches for a window.** Any visible top-level window of this process that
   was not there when the call started counts — not just one belonging to the
   dialog's thread, because comdlg32 may host the sheet on a thread of its own
   choosing and a narrower test would cut a working dialog off. The app creates
   nothing during the wait, so a new visible window *is* the dialog.
5. **The clock stops the moment a window appears.** Four seconds
   (`SPDF_WIN_PRINT_DIALOG_WATCHDOG_MS`) is how long a dialog that is going to
   appear may take to appear — it is *not* a limit on the reader, who may then
   take as long as they like. A modal dialog waiting for a human is the normal
   case and must never be cut short.
6. **On timeout it abandons the thread.** Never `TerminateThread`: a thread
   wedged inside comdlg32 holds the loader lock and a COM apartment, and killing
   it corrupts the process heap — a worse outcome than the hang it would be
   curing. So everything the call can still touch (the `PRINTDLGEXW`, the
   page-range array, the `HPROPSHEETPAGE` array, the property-sheet template and
   the choice it edits) lives in **one heap block**, and an interlocked hand-off
   decides who frees it: whichever of the waiter and the thread gets there first
   claims it, and the loser cleans up. If `PrintDlgExW` ever does return, the
   thread frees the block itself and nobody is waiting. If it never returns, the
   cost is one leaked block and one leaked thread, per process, **once**.
7. **It is asked once.** A host that abandoned a `PrintDlgEx` will do it again,
   so the outcome is remembered process-wide and every later Print goes straight
   to the in-app dialog with no wait and no second thread. The same atomic is the
   single in-flight guard: a print dialog cannot be opened twice at once.

`portable/win/tests/print_watchdog_test.c` is the regression, and it makes the
real call against a real owner window. It fails if the call does not come back.
It also passes on a healthy host: a driving thread closes any dialog that
appears and the suite then asserts the other branch — the call returned and
*nothing* was abandoned. Two counts back up the prose rather than restating it:
the elapsed time (measured 4047 ms, budget 4000) and the process's own thread
count from a Toolhelp snapshot before and after, so "reuse or refuse" is a
measurement and not a claim. On this host:

```
print_watchdog: NULL owner refused in 0 ms: Windows' print dialog needs an application window to belong to.
print_watchdog: status=4 after 4047 ms, err="Windows' print dialog did not open within 4 seconds."
print_watchdog: the second attempt refused in 0 ms with 13 thread(s), unchanged
print_watchdog_test: 13 checks, 0 failures
```

## 4. The fallback

`spdf_win_print_dialog_show()` (`spdf_win_print_dialog.cpp`) is a plain Win32
window built the way `spdf_win_properties_dialog.cpp` and `spdf_win_about.cpp`
are — no resource script (the port has none, and `build-native.cmd` discovers
`.c`/`.cpp` and nothing else), the port's own palette from
`spdf_win_chrome_theme.h`, and a dark caption through
`spdf_win_about_dark_caption`. It offers the four things a reader has to choose:

- **the printer**, from `EnumPrintersW` at level 4 (names only, so an
  unreachable network queue cannot make the list take seconds), with the default
  printer preselected — or the one remembered in `settings.yaml`;
- **Properties…**, which opens the driver's own property sheet through
  `DocumentPropertiesW` with `DM_IN_PROMPT | DM_IN_BUFFER | DM_OUT_BUFFER`. This
  is the documented way to reach printer settings without comdlg32, **and it is
  measured to work here** — driven from inside our own dialog, not just
  standalone. The DEVMODE it returns is what `CreateDCW` is given, so paper size
  and orientation reach the job through `GetDeviceCaps` exactly as
  `print_e2e_test.c`'s landscape-Letter case proves they do. Changing the printer
  drops the DEVMODE: it belongs to one driver, and carrying printer A's paper
  choice to printer B is how a job comes out on the wrong stock;
- **the pages** — all / current page / from–to. The range becomes a
  `spdf_win_print_page_range` and goes through the **same**
  `spdf_win_print_expand_ranges()` the system dialog's ranges go through, so
  "pages 3–5" means the same three sheets whichever dialog asked. "Current page"
  is greyed out when the caller did not say which page that is, rather than
  quietly standing for page 1;
- **the copies**, and **the scale** — Fit / Actual Size / Custom %, the macOS
  accessory's own three choices, read back through
  `spdf_win_print_choice_from_page()`, which is the same clamping the Scaling tab
  in Windows' dialog uses.

Print then goes straight into `spdf_win_print_run_job()` — the loop
`print_e2e_test.c` already drives to a real printer. There is one job function
and both dialogs end in it.

Two details worth knowing:

- `IsDialogMessageW` is in the modal loop, unlike in the About box or the
  properties panel. Those have two controls each; this has a combo, six radios,
  three fields and two buttons, and a print dialog that cannot be driven from the
  keyboard is not finished. Enter and Esc are handled *before* it, because with
  no dialog manager underneath there is no default-id for `IsDialogMessage` to
  find and Enter in an `ES_NUMBER` field would otherwise beep.
- **It scales with the monitor.** The app's manifest declares PerMonitorV2, so
  `CreateWindowExW`'s sizes are device pixels: on the 150% display this was
  written on, a dialog laid out in raw constants came out two thirds the size it
  should be with 15 px text in it. So the window is created at its 96-dpi size,
  `GetDpiForWindow` is asked what it landed on, and the window, every
  coordinate and the font go through `MulDiv(v, dpi, 96)`. Measured at 144 dpi:
  750x738 device px, everything inside it. `spdf_win_about.cpp` and
  `spdf_win_properties_dialog.cpp` do not do this and get away with it because
  they are a paragraph and two buttons; three groups, a combo, six radios and
  three fields do not.
- **In dark mode the visual style is stripped from every control**
  (`SetWindowTheme(h, L"", L"")`). A themed `BS_AUTORADIOBUTTON` paints its own
  label through uxtheme and ignores `SetTextColor`, so on a dark panel the label
  simply disappears. A classic control honours `WM_CTLCOLOR*`. That is plainer
  than Windows 11 and it is readable, and readable wins. In light mode nothing is
  stripped, so the normal case looks like a Windows dialog.

The reader is told why they are looking at it: one line above the buttons —
"Windows' own print dialog did not open on this computer, so this is Shenzhen
PDF's." — in the quieter of the two text colours. Not a message box: a message
box in front of a working dialog is a click spent on nothing, and the
explanation belongs where the unfamiliar window is.

`portable/win/tests/print_dialog_test.c` covers it: the printer list against
`GetDefaultPrinterW`, the range model through the shipping expansion, and the
window itself — created, its combo holding this machine's printers, its fields
taking a range and a scale, and Print returning them, driven from a second
thread with `SendMessageW` the way `properties_dialog_test.c` does. To look at
it rather than test it, `print_dialog_test.exe --hold=20 [--dark]` leaves it on
screen for twenty seconds and changes no assertion.

## 5. What persists

`settings.yaml`, through `spdf_win_settings.{h,c}`:

- `printScalingMode` (0 fit, 1 actual, 2 custom) and `printCustomScale` — keys
  that already existed and that macOS and GTK also write. Written by the shell
  (`spdf_win_cmd_window.h`), which reads them in the first place.
- `printerName` — new, **Windows-only**, written by `spdf_win_print.cpp` because
  nothing else in the app has any use for a printer name. Written **only when
  non-empty**, so a reader who has never printed gains no key; carried through
  untouched by the macOS and GTK readers, exactly as `setupPromptAnswered`
  already is. Covered by `settings_test.c`, both halves: absent while unset,
  present and byte-intact once set.

## 6. What a Windows fix would let us delete

If `PrintDlgExW` starts returning on this machine — a Windows update, a print
experience fix, a driver change — nothing has to be undone in a hurry: the
watchdog stops firing and the reader stops seeing the fallback, on its own. When
it is known to be fixed *everywhere the app ships*, these can go:

- `spdf_win_print_dialog_system.cpp` collapses to the plain
  `PrintDlgExW(&pd)` call it replaced: no thread, no heap block, no hand-off, no
  `g_system_state`, no window watching. About 260 lines to about 90.
- `spdf_win_print_dialog.cpp` and `spdf_win_print_dialog_run.cpp` — the whole
  in-app dialog — become dead code, along with `printerName` (Windows' dialog
  remembers the printer itself) and the `note` parameter.
- `print_watchdog_test.c` and `print_dialog_test.c` go with them, and
  `print_dialog_probe.c` becomes a historical note.
- `spdf_win_print_dialog_choose.cpp` loses its second rung and shrinks to the
  first, and with it `spdf_win_print_document_for_view()` loses its reason to
  exist — `spdf_win_print_document_ex()` is the only entry point again.

That file split is itself worth keeping in mind. `spdf_win_print.cpp` is the
JOB — permissions, one page onto a DC, `StartDoc`/`EndDoc` — and nothing else;
choosing a dialog needs `settings.yaml`, and `settings.yaml` needs the state
shell, the YAML codec, the recents store and the watcher. Putting the
orchestration in `spdf_win_print.cpp` compiled fine and broke
`light_theme_test`'s link, which is how the dependency was noticed. The
orchestration lives in `spdf_win_print_dialog_choose.cpp` so that the two
suites that link the job — `light_theme_test.c` and `print_e2e_test.c` — pay
for nothing but the job.

What would **not** go, and should not: `spdf_win_print_run_job()`, the split
that lets a print job be driven with no dialog at all, and `print_e2e_test.c`
around it. That split was made because the dialog could not be reached, but it
is the reason printing is tested at all, and it would be worth having on a
machine where every dialog worked perfectly.

## 7. Loose end

`spdf_win_print_scaling.h`'s header comment still says the Scaling page "only
exists inside PrintDlgEx, which cannot show a dialog while the session is
locked". Both halves of that are now wrong on this host — the session is
unlocked and `PrintDlgExW` fails anyway — and the page's three choices are also
offered by the in-app dialog. That file belongs to another track this round; the
correction is a comment-only patch.
