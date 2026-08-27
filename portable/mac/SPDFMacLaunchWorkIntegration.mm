#import "SPDFMacLaunchWorkIntegration.h"

#import "SPDFMacDelegatePrivate.h"
#import "SPDFMacSupport.h"

@interface ShenzhenMacDelegate (SPDFMacLaunchWorkIntegrationPrivate)
@property(nonatomic, readonly) SPDFMacLaunchWorkCoordinator* launchWorkCoordinator;
- (void)loadOutlineForCurrentDocumentAsync;
- (void)loadCommentsForCurrentDocumentAsync;
- (void)preloadInactiveTabsWithCompletion:(dispatch_block_t)completion;
@end

@implementation ShenzhenMacDelegate (SPDFMacLaunchWorkIntegration)

- (void)spdf_scheduleIdleNearbyPageRendersForGeneration:(NSUInteger)generation preferredPage:(NSInteger)preferredPage {
    NSString* path = [_path copy];
    if (!path.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self->_pageScrollView displayIfNeeded];
      [self.launchWorkCoordinator beginCycleAtStage:SPDFMacLaunchWarmStageActiveDocument
                                            context:@{
                                                @"generation" : @(generation),
                                                @"path" : path,
                                                @"savedFind" : @(-1),
                                                @"search" : @"",
                                                @"restoreSearch" : @NO,
                                                @"page" : @(preferredPage)
                                            }];
    });
}

- (void)spdf_scheduleIdlePostFirstPaintWorkForGeneration:(NSUInteger)generation
                                                    path:(NSString*)path
                                     savedFindMatchIndex:(NSInteger)savedFindMatchIndex
                                           restoreSearch:(BOOL)restoreSearch
                                     preferredRenderPage:(NSInteger)preferredRenderPage {
    if (!path.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self->_pageScrollView displayIfNeeded];
      [self.launchWorkCoordinator beginCycleAtStage:SPDFMacLaunchWarmStageMetadata
                                            context:@{
                                                @"generation" : @(generation),
                                                @"path" : path,
                                                @"savedFind" : @(savedFindMatchIndex),
                                                @"search" : [_searchField.stringValue copy] ?: @"",
                                                @"restoreSearch" : @(restoreSearch),
                                                @"page" : @(preferredRenderPage)
                                            }];
    });
}

- (void)runLaunchWarmStage:(SPDFMacLaunchWarmStage)stage
                generation:(NSUInteger)generation
                   context:(NSDictionary*)context {
    NSString* path = context[@"path"];
    if (!path.length || ![_path isEqualToString:path]) {
        [self.launchWorkCoordinator completeCycleForGeneration:generation];
        return;
    }
    spdf_launch_profile_log(@"idle warm stage=%ld generation=%lu", (long)stage, (unsigned long)generation);
    if (stage == SPDFMacLaunchWarmStageMetadata) {
        [self loadOutlineForCurrentDocumentAsync];
        [self loadCommentsForCurrentDocumentAsync];
        return;
    }
    if ([context[@"generation"] unsignedIntegerValue] != _renderGeneration) {
        [self.launchWorkCoordinator completeCycleForGeneration:generation];
        return;
    }
    NSInteger preferredPage = [context[@"page"] integerValue];
    if (stage == SPDFMacLaunchWarmStageActiveDocument) {
        [self enqueueZoomSeedCachesForGeneration:_renderGeneration preferredPage:preferredPage includeWholeBase:YES];
        [self enqueueNearbyPageRendersForGeneration:_renderGeneration preferredPage:preferredPage];
        NSString* capturedSearch = context[@"search"];
        if ([context[@"restoreSearch"] boolValue] && capturedSearch.length > 0 &&
            [_searchField.stringValue isEqualToString:capturedSearch]) {
            _pendingFindPreferredMatchIndex = [context[@"savedFind"] integerValue];
            _pendingFindPreferredPage = -1;
            [self startFindForCurrentQueryResetSavedIndex:NO revealMatch:NO];
        }
        return;
    }
    if (stage == SPDFMacLaunchWarmStageInactiveTabs) {
        if (!spdf_mac_launch_can_start_inactive_work(_renderQueue.operationCount, _preloadQueue.operationCount,
                                                     _minimapQueue.operationCount, _zoomSeedRenderQueue.operationCount,
                                                     _cacheRenderQueue.operationCount,
                                                     _backgroundRenderQueue.operationCount)) {
            [self.launchWorkCoordinator beginCycleAtStage:SPDFMacLaunchWarmStageInactiveTabs context:context];
            return;
        }
        [self preloadInactiveTabsWithCompletion:^{
          [self.launchWorkCoordinator completeCycleForGeneration:generation];
        }];
    }
}

@end
