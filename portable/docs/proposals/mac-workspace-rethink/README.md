# Whole-reader organization proposal

Start with [decision and validation](decision-and-validation.md). The
[architecture inventory](architecture.md) records the alternatives, and the
[critic record](critic.md) distinguishes corrected prototype failures from
untested native behavior. The separate [availability bug fix](bug-audit.md)
is already built; the interface redesign is only a proposal.

`reader-workspace.fragment.html` is the canonical interactive source. It is
also delivered inline through the visualization skill. Generated standalone
previews are ignored because they embed that skill's runtime.

To preview using an installed visualization skill, pass its `scripts/render.py`
path as `$SIDEBAR_VISUALIZE_RENDERER`:

```sh
python3 "$SIDEBAR_VISUALIZE_RENDERER" reader-workspace.fragment.html prototype.html --force
python3 -m http.server 61208 --bind 127.0.0.1
```

The captured medium and compact fixtures change only `design.height` from
594 to 418 and 296 respectively. Their browser viewports are 800×500 and
560×380. The preview wrapper contributes a 16px margin around the mock window.
The normal prototype exposes height and navigation alternatives through the
host's design controls.
