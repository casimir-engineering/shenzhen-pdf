#import "SPDFMacCollectionIntegration.h"

@interface ShenzhenMacDelegate (SPDFMacCollectionPaletteHost)
- (void)focusOpenDocumentTabForPath:(NSString*)path;
- (NSArray<NSDictionary*>*)openDocumentPaletteCandidates;
- (NSString*)shortProvenanceForPath:(NSString*)path;
- (NSString*)pathForStateFile:(NSString*)name;
- (void)selectFirstPaletteResult;
- (void)updatePalettePanelFramePreservingTop:(BOOL)preserve;
- (void)goToPage:(NSInteger)page preserveSinglePagePosition:(BOOL)preserve;
@end

@interface ShenzhenMacDelegate (SPDFMacCollectionPalette)
- (NSArray*)favoriteResultsForQuery:(NSString*)query prefix:(NSString*)prefix;
- (NSArray*)collectionPaletteSupplementaryRowsForQuery:(NSString*)query excludingOpenPaths:(NSSet*)paths;
- (void)refreshPaletteResults;
- (BOOL)openCollectionPaletteResult:(NSDictionary*)result;
- (void)collectionNavigateResult:(NSDictionary*)result path:(NSString*)path attempts:(NSInteger)attempts;
@end
