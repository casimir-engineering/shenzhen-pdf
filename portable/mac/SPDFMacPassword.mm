#import "SPDFMacPassword.h"

#include <sys/stat.h>

static void spdf_secure_zero(void* bytes, size_t length) {
    volatile unsigned char* cursor = (volatile unsigned char*)bytes;
    while (length--) *cursor++ = 0;
}

@interface SPDFPasswordCredential () {
    char* _bytes;
    size_t _length;
}
@end

@implementation SPDFPasswordCredential

- (instancetype)initWithPassword:(NSString*)password {
    self = [super init];
    if (!self) return nil;
    NSData* data = [password dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO] ?: [NSData data];
    _length = data.length;
    _bytes = (char*)calloc(_length + 1, 1);
    if (!_bytes) return nil;
    if (_length) memcpy(_bytes, data.bytes, _length);
    return self;
}

- (void)withUTF8Password:(void (^)(const char* password))block {
    if (block) block(_bytes ?: "");
}

- (void)dealloc {
    if (_bytes) {
        spdf_secure_zero(_bytes, _length + 1);
        free(_bytes);
    }
}

@end

@interface SPDFPasswordStoreEntry : NSObject
@property(nonatomic, copy) NSString* identity;
@property(nonatomic, copy) NSString* cacheToken;
@property(nonatomic, strong) SPDFPasswordCredential* credential;
@end

@implementation SPDFPasswordStoreEntry
@end

static NSString* spdf_standardized_password_path(NSString* path) {
    if (!path.length) return @"";
    return path.stringByStandardizingPath ?: path;
}

static NSString* spdf_password_source_identity(NSString* path) {
    NSString* standardized = spdf_standardized_password_path(path);
    if (!standardized.length) return nil;
    struct stat st;
    if (lstat(standardized.fileSystemRepresentation, &st) != 0) return nil;
#if defined(__APPLE__)
    long mtimeNanoseconds = st.st_mtimespec.tv_nsec;
    long long mtimeSeconds = st.st_mtimespec.tv_sec;
#else
    long mtimeNanoseconds = st.st_mtim.tv_nsec;
    long long mtimeSeconds = st.st_mtim.tv_sec;
#endif
    return [NSString stringWithFormat:@"%@:%llu:%llu:%llu:%lld:%ld", standardized,
                                      (unsigned long long)st.st_dev, (unsigned long long)st.st_ino,
                                      (unsigned long long)st.st_size, mtimeSeconds, mtimeNanoseconds];
}

@implementation SPDFPasswordCredentialStore {
    NSLock* _lock;
    NSMutableDictionary<NSString*, SPDFPasswordStoreEntry*>* _entries;
}

+ (instancetype)sharedStore {
    static SPDFPasswordCredentialStore* store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [[SPDFPasswordCredentialStore alloc] initPrivate]; });
    return store;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        _entries = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)init {
    return [SPDFPasswordCredentialStore sharedStore];
}

- (SPDFPasswordCredential*)credentialForSourcePath:(NSString*)sourcePath {
    NSString* path = spdf_standardized_password_path(sourcePath);
    NSString* identity = spdf_password_source_identity(path);
    if (!path.length || !identity.length) {
        if (path.length) [self invalidateCredentialForSourcePath:path];
        return nil;
    }

    [_lock lock];
    SPDFPasswordStoreEntry* entry = _entries[path];
    if (entry && ![entry.identity isEqualToString:identity]) {
        [_entries removeObjectForKey:path];
        entry = nil;
    }
    SPDFPasswordCredential* credential = entry.credential;
    [_lock unlock];
    return credential;
}

- (void)setCredential:(SPDFPasswordCredential*)credential forSourcePath:(NSString*)sourcePath {
    NSString* path = spdf_standardized_password_path(sourcePath);
    NSString* identity = spdf_password_source_identity(path);
    if (!credential || !path.length || !identity.length) return;

    SPDFPasswordStoreEntry* entry = [[SPDFPasswordStoreEntry alloc] init];
    entry.identity = identity;
    entry.cacheToken = [identity stringByAppendingFormat:@":%@", NSUUID.UUID.UUIDString];
    entry.credential = credential;
    [_lock lock];
    _entries[path] = entry;
    [_lock unlock];
}

- (void)invalidateCredentialForSourcePath:(NSString*)sourcePath {
    NSString* path = spdf_standardized_password_path(sourcePath);
    if (!path.length) return;
    [_lock lock];
    [_entries removeObjectForKey:path];
    [_lock unlock];
}

- (NSString*)sourceIdentityTokenForSourcePath:(NSString*)sourcePath {
    return spdf_password_source_identity(sourcePath);
}

- (NSString*)cacheTokenForSourcePath:(NSString*)sourcePath {
    NSString* path = spdf_standardized_password_path(sourcePath);
    NSString* identity = spdf_password_source_identity(path);
    if (!path.length || !identity.length) {
        if (path.length) [self invalidateCredentialForSourcePath:path];
        return [path stringByAppendingString:@":missing"];
    }

    [_lock lock];
    SPDFPasswordStoreEntry* entry = _entries[path];
    if (entry && ![entry.identity isEqualToString:identity]) {
        [_entries removeObjectForKey:path];
        entry = nil;
    }
    NSString* token = entry.cacheToken ?: [identity stringByAppendingString:@":no-credential"];
    [_lock unlock];
    return token;
}

- (void)removeAllCredentials {
    [_lock lock];
    [_entries removeAllObjects];
    [_lock unlock];
}

@end

spdf_document* SPDFOpenDocumentWithCredential(NSString* openPath, SPDFPasswordCredential* credential,
                                               spdf_open_status* status, spdf_authentication* authentication,
                                               char* error, size_t errorLength) {
    if (!credential)
        return spdf_open_with_password(openPath.fileSystemRepresentation, NULL, status, authentication, error,
                                       errorLength);
    __block spdf_document* document = NULL;
    [credential withUTF8Password:^(const char* password) {
      document = spdf_open_with_password(openPath.fileSystemRepresentation, password, status, authentication, error,
                                         errorLength);
    }];
    return document;
}

spdf_document* SPDFOpenDocumentWithStoredCredential(NSString* openPath, NSString* sourcePath, spdf_open_status* status,
                                                     spdf_authentication* authentication, char* error,
                                                     size_t errorLength) {
    SPDFPasswordCredentialStore* store = SPDFPasswordCredentialStore.sharedStore;
    SPDFPasswordCredential* credential = [store credentialForSourcePath:sourcePath];
    spdf_open_status localStatus = SPDF_OPEN_ERROR;
    spdf_document* document = SPDFOpenDocumentWithCredential(openPath, credential, &localStatus, authentication, error,
                                                             errorLength);
    if (credential && localStatus == SPDF_OPEN_BAD_PASSWORD) [store invalidateCredentialForSourcePath:sourcePath];
    if (status) *status = localStatus;
    return document;
}

@interface SPDFPasswordSheetController () <NSWindowDelegate>
@end

@implementation SPDFPasswordSheetController {
    __weak NSWindow* _parentWindow;
    NSPanel* _panel;
    NSSecureTextField* _passwordField;
    NSTextField* _statusField;
    NSButton* _unlockButton;
    NSButton* _cancelButton;
    NSProgressIndicator* _progress;
    SPDFPasswordAttemptHandler _attemptHandler;
    dispatch_block_t _cancelHandler;
    BOOL _attemptInProgress;
    BOOL _finished;
}

- (instancetype)initWithParentWindow:(NSWindow*)parentWindow
                         displayName:(NSString*)displayName
                      attemptHandler:(SPDFPasswordAttemptHandler)attemptHandler
                       cancelHandler:(dispatch_block_t)cancelHandler {
    self = [super init];
    if (!self) return nil;
    _parentWindow = parentWindow;
    _attemptHandler = [attemptHandler copy];
    _cancelHandler = [cancelHandler copy];
    [self buildPanelForDisplayName:displayName];
    return self;
}

- (void)buildPanelForDisplayName:(NSString*)displayName {
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 430, 190)
                                        styleMask:NSWindowStyleMaskTitled
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    _panel.title = @"Password Required";
    _panel.releasedWhenClosed = NO;
    _panel.delegate = self;

    NSView* content = _panel.contentView;
    NSTextField* message = [NSTextField wrappingLabelWithString:
                                            [NSString stringWithFormat:@"Enter the password to open %@.",
                                                                       displayName.length ? displayName : @"this PDF"]];
    message.translatesAutoresizingMaskIntoConstraints = NO;
    message.font = [NSFont systemFontOfSize:13];
    [content addSubview:message];

    _passwordField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
    _passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    _passwordField.placeholderString = @"Password";
    _passwordField.target = self;
    _passwordField.action = @selector(attemptUnlock:);
    [content addSubview:_passwordField];

    _statusField = [NSTextField labelWithString:@""];
    _statusField.translatesAutoresizingMaskIntoConstraints = NO;
    _statusField.textColor = NSColor.systemRedColor;
    _statusField.font = [NSFont systemFontOfSize:12];
    [content addSubview:_statusField];

    _progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _progress.translatesAutoresizingMaskIntoConstraints = NO;
    _progress.style = NSProgressIndicatorStyleSpinning;
    _progress.controlSize = NSControlSizeSmall;
    _progress.hidden = YES;
    [content addSubview:_progress];

    _cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelAction:)];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.keyEquivalent = @"\e";
    [content addSubview:_cancelButton];

    _unlockButton = [NSButton buttonWithTitle:@"Unlock" target:self action:@selector(attemptUnlock:)];
    _unlockButton.translatesAutoresizingMaskIntoConstraints = NO;
    _unlockButton.keyEquivalent = @"\r";
    [content addSubview:_unlockButton];

    [NSLayoutConstraint activateConstraints:@[
        [message.topAnchor constraintEqualToAnchor:content.topAnchor constant:22],
        [message.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],
        [message.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [_passwordField.topAnchor constraintEqualToAnchor:message.bottomAnchor constant:14],
        [_passwordField.leadingAnchor constraintEqualToAnchor:message.leadingAnchor],
        [_passwordField.trailingAnchor constraintEqualToAnchor:message.trailingAnchor],
        [_statusField.topAnchor constraintEqualToAnchor:_passwordField.bottomAnchor constant:7],
        [_statusField.leadingAnchor constraintEqualToAnchor:_passwordField.leadingAnchor],
        [_statusField.trailingAnchor constraintLessThanOrEqualToAnchor:_progress.leadingAnchor constant:-8],
        [_progress.centerYAnchor constraintEqualToAnchor:_statusField.centerYAnchor],
        [_progress.trailingAnchor constraintEqualToAnchor:_passwordField.trailingAnchor],
        [_progress.widthAnchor constraintEqualToConstant:16],
        [_progress.heightAnchor constraintEqualToConstant:16],
        [_cancelButton.trailingAnchor constraintEqualToAnchor:_unlockButton.leadingAnchor constant:-10],
        [_cancelButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-18],
        [_unlockButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],
        [_unlockButton.centerYAnchor constraintEqualToAnchor:_cancelButton.centerYAnchor],
    ]];
}

- (void)begin {
    NSWindow* parent = _parentWindow;
    if (!parent || _finished) return;
    [parent beginSheet:_panel completionHandler:nil];
    [_panel makeFirstResponder:_passwordField];
}

- (void)setAttemptInProgress:(BOOL)inProgress {
    _attemptInProgress = inProgress;
    _passwordField.enabled = !inProgress;
    _unlockButton.enabled = !inProgress;
    _cancelButton.enabled = !inProgress;
    _progress.hidden = !inProgress;
    if (inProgress)
        [_progress startAnimation:nil];
    else
        [_progress stopAnimation:nil];
}

- (void)attemptUnlock:(id)sender {
    (void)sender;
    if (_finished || _attemptInProgress || !_attemptHandler) return;
    __block SPDFPasswordCredential* credential;
    @autoreleasepool {
        credential = [[SPDFPasswordCredential alloc] initWithPassword:_passwordField.stringValue];
        _passwordField.stringValue = @"";
    }
    _statusField.stringValue = @"";
    [self setAttemptInProgress:YES];
    __weak SPDFPasswordSheetController* weakSelf = self;
    _attemptHandler(credential, ^(SPDFPasswordAttemptResult result, NSString* detail) {
      dispatch_async(dispatch_get_main_queue(), ^{
        SPDFPasswordSheetController* self = weakSelf;
        if (!self || self->_finished) return;
        [self setAttemptInProgress:NO];
        if (result == SPDFPasswordAttemptSucceeded) {
            [self finishWithoutCancel];
            return;
        }
        self->_statusField.stringValue = detail.length
                                             ? detail
                                             : (result == SPDFPasswordAttemptIncorrect ? @"Incorrect password."
                                                                                       : @"The PDF could not be opened.");
        [self->_panel makeFirstResponder:self->_passwordField];
      });
    });
}

- (void)finishWithoutCancel {
    if (_finished) return;
    _finished = YES;
    NSWindow* parent = _parentWindow;
    if (parent && parent.attachedSheet == _panel) [parent endSheet:_panel];
    [_panel orderOut:nil];
    _attemptHandler = nil;
    _cancelHandler = nil;
}

- (void)cancelAction:(id)sender {
    (void)sender;
    [self cancel];
}

- (void)cancel {
    if (_finished) return;
    _finished = YES;
    NSWindow* parent = _parentWindow;
    if (parent && parent.attachedSheet == _panel) [parent endSheet:_panel];
    [_panel orderOut:nil];
    dispatch_block_t handler = _cancelHandler;
    _attemptHandler = nil;
    _cancelHandler = nil;
    if (handler) handler();
}

@end
