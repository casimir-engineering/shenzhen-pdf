#import "SPDFMacTabStripStyle.h"

// Half a 28pt-tall tab, i.e. fully rounded ends. 7pt read as a chamfer and
// 10pt still read as under-rounded; NSBezierPath clamps to half the shorter
// side, so this is the roundest a tab of this height can be.
const CGFloat kSPDFTabCornerRadius = 14.0;

// Outline widths. Both are even multiples of a device pixel at 1x and 2x once
// inset by half their width, which is what keeps the hairline crisp; 1.4 (the
// old selected width) is neither, so it smeared at both scales.
static const CGFloat kUnselectedStrokeWidth = 1.0;
static const CGFloat kSelectedStrokeWidth = 2.0;

// Neutral outline strength for an unselected present tab. separatorColor ships
// at alpha 0.098 — a hairline meant to sit between two panes of the same
// colour, far too faint to read as a tab edge — so the alpha is raised the way
// the strip's overflow button already raises it. Deliberately translucent and
// well short of the selected tab's 0.95 accent: the unselected tab needs an
// edge, not equal billing.
// separatorColor ships at 0.098, far too faint to read as a tab edge. 0.42
// overshot and 0.26 was still heavier than wanted; 0.18 is the quietest value
// that still gives every tab a discernible edge against a strip whose colour
// is byte-identical to the tab fill.
static const CGFloat kUnselectedStrokeAlpha = 0.18;

SPDFTabStyle spdf_tab_style_for_state(BOOL selected, BOOL missing) {
    CGFloat width = selected ? kSelectedStrokeWidth : kUnselectedStrokeWidth;
    if (missing) {
        return (SPDFTabStyle){.fillRole = SPDFTabStyleRoleAlert,
                              .fillAlpha = selected ? 0.36 : 0.22,
                              .strokeRole = SPDFTabStyleRoleAlert,
                              .strokeAlpha = selected ? 0.95 : 0.65,
                              .strokeWidth = width};
    }
    if (selected) {
        return (SPDFTabStyle){.fillRole = SPDFTabStyleRoleAccent,
                              .fillAlpha = 0.34,
                              .strokeRole = SPDFTabStyleRoleAccent,
                              .strokeAlpha = 0.95,
                              .strokeWidth = width};
    }
    return (SPDFTabStyle){.fillRole = SPDFTabStyleRoleControlBackground,
                          .fillAlpha = 0.0,
                          .strokeRole = SPDFTabStyleRoleSeparator,
                          .strokeAlpha = kUnselectedStrokeAlpha,
                          .strokeWidth = width};
}

CGFloat spdf_tab_stroke_inset(CGFloat strokeWidth) {
    return strokeWidth / 2.0;
}

NSColor* spdf_tab_style_color(SPDFTabStyleRole role, CGFloat alpha) {
    NSColor* base = nil;
    switch (role) {
        case SPDFTabStyleRoleAccent:
            base = NSColor.controlAccentColor;
            break;
        case SPDFTabStyleRoleAlert:
            base = NSColor.systemRedColor;
            break;
        case SPDFTabStyleRoleSeparator:
            base = NSColor.separatorColor;
            break;
        case SPDFTabStyleRoleControlBackground:
            base = NSColor.controlBackgroundColor;
            break;
    }
    return alpha > 0.0 ? [base colorWithAlphaComponent:alpha] : base;
}
