#import "SPDFMacMarkdownDelegatePrivate.h"

#import "markdown/SPDFMarkdown.h"

// The markdown-only reading-theme toggle: one toolbar button right of the
// A-/A+ text-size pill plus the persisted "markdownTheme" preference it
// drives. Wired exactly like the font-size controls: hidden for PDF tabs,
// refreshed by updateMarkdownFontControls, mirrored into the toolbar overflow
// menu, applied to the active session via the viewport-preserving rerender,
// and adopted by cached sessions before activation.

@implementation ShenzhenMacDelegate (SPDFMacMarkdownThemeIntegration)

- (SPDFMarkdownThemeVariant)markdownThemeVariant {
    return _markdownDarkTheme ? SPDFMarkdownThemeVariantDark : SPDFMarkdownThemeVariantLight;
}

// While LIGHT is active the button shows the moon (pressing it switches to
// dark); while DARK is active it shows the sun (pressing switches to light).
- (NSString*)markdownThemeToggleTitle {
    return _markdownDarkTheme ? @"Switch to Light Reading Theme" : @"Switch to Dark Reading Theme";
}

- (void)buildMarkdownThemeToolbarButton {
    NSButton* button = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleMarkdownReadingTheme:)];
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.imagePosition = NSImageOnly;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:32].active = YES;
    [button setContentHuggingPriority:NSLayoutPriorityRequired
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    [button setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    button.hidden = YES;  // markdown-only; updateMarkdownThemeControls reveals it
    _markdownThemeButton = button;
    [self updateMarkdownThemeControls];
}

- (void)updateMarkdownThemeControls {
    if (!_markdownThemeButton) return;
    BOOL markdownActive = [self isMarkdownActive];
    _markdownThemeButton.hidden = !markdownActive;
    if (!markdownActive) return;
    NSString* symbol = _markdownDarkTheme ? @"sun.max" : @"moon.stars";
    _markdownThemeButton.image = [NSImage imageWithSystemSymbolName:symbol
                                           accessibilityDescription:self.markdownThemeToggleTitle];
    _markdownThemeButton.toolTip = self.markdownThemeToggleTitle;
    _markdownThemeButton.accessibilityLabel = self.markdownThemeToggleTitle;
}

- (void)toggleMarkdownReadingTheme:(id)sender {
    (void)sender;
    if (![self isMarkdownActive]) return;
    _markdownDarkTheme = !_markdownDarkTheme;
    [self savePersistentState];
    [self.activeMarkdownSession applyThemeVariant:self.markdownThemeVariant];
    [self updateControlsForActiveMarkdown];
}

// Overflow-menu mirror, called from rebuildToolbarOverflowMenuWithHiddenViews:
// (the theme button collapses into the overflow with the text-size pill).
- (void)addMarkdownThemeOverflowItemsToMenu:(NSMenu*)menu hiddenViews:(NSSet<NSView*>*)hiddenViews {
    if (![hiddenViews containsObject:_markdownThemeButton]) return;
    [self addOverflowItemWithTitle:self.markdownThemeToggleTitle
                            action:@selector(toggleMarkdownReadingTheme:)
                              menu:menu
                             state:NSControlStateValueOff
                           enabled:YES];
}

@end
