#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <math.h>

static NSString *InterfaceLanguage(void) {
    NSString *choice = [NSUserDefaults.standardUserDefaults stringForKey:@"interfaceLanguage"];
    if ([choice isEqualToString:@"en"] || [choice isEqualToString:@"ru"]) return choice;
    return [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"] ? @"ru" : @"en";
}
static NSString *L(NSString *text) {
    if (!text || [InterfaceLanguage() isEqualToString:@"ru"]) return text;
    static NSDictionary *translations;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ translations = @{
            @"Подробная панель Touch Bar недоступна": @"Expanded Touch Bar is unavailable",
            @"нет данных": @"no data",
            @"обновляю…": @"refreshing…",
            @"%ldд %ldч": @"%ldd %ldh",
            @"%ldч %ldм": @"%ldh %ldm",
            @"%ldм": @"%ldm",
            @"Неделя": @"Week",
            @"5 часов": @"5 hours",
            @"7д": @"7d",
            @"5ч": @"5h",
            @"Подключение…": @"Connecting…",
            @"5 часов: —": @"5 hours: —",
            @"Неделя: —": @"Week: —",
            @"Обновить сейчас": @"Refresh now",
            @"Показать лимиты на Touch Bar": @"Show limits on Touch Bar",
            @"Оформление": @"Appearance",
            @"Полоски прогресса": @"Progress bars",
            @"Компактные проценты": @"Compact percentages",
            @"Кольца": @"Rings",
            @"Выключить помощник": @"Quit helper",
            @"Остаток лимитов Codex: 5 часов и неделя": @"Remaining Codex limits: 5 hours and week",
            @"Соединение прервано": @"Connection interrupted",
            @"Codex CLI не найден. Откройте ChatGPT.": @"Codex CLI not found. Open ChatGPT.",
            @"Некорректный ответ CLI": @"Invalid CLI response",
            @"CLI недоступен. Повтор через 30 секунд.": @"CLI unavailable. Retrying in 30 seconds.",
            @"Не удалось запустить CLI": @"Could not start CLI",
            @"Время подключения истекло": @"Connection timed out",
            @"CLI не поддерживает подключение": @"CLI does not support this connection",
            @"Не удалось получить лимиты": @"Could not fetch limits",
            @"Сервис не вернул окна 5 часов / 7 дней": @"Service did not return 5-hour / 7-day limits",
            @"Сервис не ответил. Повтор через 30 секунд.": @"Service did not respond. Retrying in 30 seconds.",
            @"5ч %@ · 7д %@": @"5h %@ · 7d %@",
            @"5 часов: %@ · ↻ %@": @"5 hours: %@ · ↻ %@",
            @"Неделя: %@ · ↻ %@": @"Week: %@ · ↻ %@",
            @"5 часов: осталось %@ · сброс %@": @"5 hours: %@ remaining · resets %@",
            @"Неделя: осталось %@ · сброс %@": @"Week: %@ remaining · resets %@",
            @"Данные устарели, обновляю…": @"Data is stale, refreshing…",
            @"Автообновление каждые 30 секунд": @"Refreshes every 30 seconds",
            @" · Touch Bar API недоступен": @" · Touch Bar API unavailable",
            @"Обновить": @"Refresh",
            @"Закрыть": @"Close",
    }; });
    return translations[text] ?: text;
}

// Private macOS entry points are checked before use; the menu-bar view is public API.
@interface NSTouchBarItem (SystemTray)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end
@interface NSTouchBar (SystemModal)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)bar systemTrayItemIdentifier:(NSString *)identifier;
+ (void)presentSystemModalTouchBar:(NSTouchBar *)bar placement:(long long)placement systemTrayItemIdentifier:(NSString *)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)bar;
@end

static NSString * const TrayID = @"local.codex.touchbar.limits";
static NSDictionary *Windows(NSDictionary *result) {
    NSDictionary *all = [result[@"rateLimitsByLimitId"] isKindOfClass:NSDictionary.class] ? result[@"rateLimitsByLimitId"] : nil;
    NSDictionary *bucket = [all[@"codex"] isKindOfClass:NSDictionary.class] ? all[@"codex"] : nil;
    if (!bucket && [result[@"rateLimits"] isKindOfClass:NSDictionary.class]) {
        NSDictionary *legacy = result[@"rateLimits"];
        if (!legacy[@"limitId"] || [legacy[@"limitId"] isEqual:@"codex"]) bucket = legacy;
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"primary", @"secondary"]) {
        NSDictionary *w = [bucket[key] isKindOfClass:NSDictionary.class] ? bucket[key] : nil;
        if (![w[@"windowDurationMins"] isKindOfClass:NSNumber.class] || ![w[@"usedPercent"] isKindOfClass:NSNumber.class] || ![w[@"resetsAt"] isKindOfClass:NSNumber.class]) continue;
        if (!isfinite([w[@"usedPercent"] doubleValue])) continue;
        NSInteger mins = [w[@"windowDurationMins"] integerValue];
        if (mins == 300) out[@"five"] = w;
        if (mins == 10080) out[@"week"] = w;
    }
    return out;
}
static NSString *Percent(NSDictionary *window, NSDate *now) {
    if (!window || [window[@"resetsAt"] doubleValue] <= now.timeIntervalSince1970) return @"—";
    double remaining = fmax(0, fmin(100, 100 - [window[@"usedPercent"] doubleValue]));
    return [NSString stringWithFormat:@"%.0f%%", remaining];
}
static NSString *ResetText(NSDictionary *window) {
    if (!window) return L(@"нет данных");
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:[InterfaceLanguage() isEqualToString:@"ru"] ? @"ru_RU" : @"en_US"];
    fmt.dateFormat = @"d MMM, HH:mm";
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:[window[@"resetsAt"] doubleValue]]];
}

static NSString *Countdown(NSDictionary *window) {
    if (!window) return L(@"нет данных");
    NSTimeInterval seconds = [window[@"resetsAt"] doubleValue] - NSDate.date.timeIntervalSince1970;
    if (seconds <= 0) return L(@"обновляю…");
    NSInteger mins = (NSInteger)ceil(seconds / 60);
    if (mins >= 1440) return [NSString stringWithFormat:L(@"%ldд %ldч"), (long)(mins / 1440), (long)(mins % 1440 / 60)];
    if (mins >= 60) return [NSString stringWithFormat:L(@"%ldч %ldм"), (long)(mins / 60), (long)(mins % 60)];
    return [NSString stringWithFormat:L(@"%ldм"), (long)mins];
}
static NSColor *QuotaColor(double remaining) {
    if (remaining < 0) return [NSColor colorWithWhite:0.45 alpha:1];
    if (remaining <= 15) return [NSColor colorWithRed:1 green:0.35 blue:0.40 alpha:1];
    if (remaining <= 35) return [NSColor colorWithRed:1 green:0.74 blue:0.28 alpha:1];
    return [NSColor colorWithRed:0.32 green:0.88 blue:0.68 alpha:1];
}

// All styles use the same data. -1 is unavailable, never a guessed 100%.
@interface QuotaView : NSView
@property double fiveRemaining;
@property double weekRemaining;
@property NSInteger style;
@property BOOL compact;
@end
@implementation QuotaView
- (NSSize)intrinsicContentSize { return self.compact ? NSMakeSize(54, 30) : NSMakeSize(360, 30); }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithWhite:0.075 alpha:1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6] fill];
    CGFloat cell = self.bounds.size.width / 2;
    for (NSInteger i = 0; i < 2; ++i) {
        double remaining = i ? self.weekRemaining : self.fiveRemaining;
        NSString *label = i ? L(@"Неделя") : L(@"5 часов");
        NSString *shortLabel = i ? L(@"7д") : L(@"5ч");
        NSString *percent = remaining < 0 ? @"—" : [NSString stringWithFormat:@"%.0f%%", remaining];
        if (self.compact) {
            // A Control Strip item has roughly a 55 pt slot; never let the
            // full-width gauge be silently pushed out of the visible area.
            CGFloat y = i ? 4 : 17;
            NSDictionary *smallLabel = @{NSFontAttributeName:[NSFont systemFontOfSize:9 weight:NSFontWeightSemibold], NSForegroundColorAttributeName:[NSColor colorWithWhite:0.76 alpha:1]};
            NSDictionary *smallNumber = @{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightBold], NSForegroundColorAttributeName:NSColor.whiteColor};
            [QuotaColor(remaining) setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(4, y + 1, 5, 5)] fill];
            [shortLabel drawAtPoint:NSMakePoint(12, y - 1) withAttributes:smallLabel];
            CGFloat numberWidth = [percent sizeWithAttributes:smallNumber].width;
            [percent drawAtPoint:NSMakePoint(self.bounds.size.width - 4 - numberWidth, y - 1) withAttributes:smallNumber];
            continue;
        }
        CGFloat left = i * cell + 8;
        CGFloat width = cell - 16;
        NSDictionary *caption = @{NSFontAttributeName:[NSFont systemFontOfSize:9 weight:NSFontWeightMedium], NSForegroundColorAttributeName:[NSColor colorWithWhite:0.70 alpha:1]};
        NSDictionary *number = @{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightSemibold], NSForegroundColorAttributeName:NSColor.whiteColor};
        NSColor *color = QuotaColor(remaining);
        if (self.style == 1) {
            NSString *text = [NSString stringWithFormat:@"%@ %@", shortLabel, percent];
            [text drawAtPoint:NSMakePoint(left, 8) withAttributes:number];
        } else if (self.style == 2) {
            NSPoint center = NSMakePoint(left + 11, 15);
            NSBezierPath *track = [NSBezierPath bezierPath];
            [track appendBezierPathWithArcWithCenter:center radius:9 startAngle:0 endAngle:360];
            track.lineWidth = 3;
            [[NSColor colorWithWhite:0.23 alpha:1] setStroke]; [track stroke];
            if (remaining > 0) {
                NSBezierPath *arc = [NSBezierPath bezierPath];
                [arc appendBezierPathWithArcWithCenter:center radius:9 startAngle:90 endAngle:90 - remaining * 3.6 clockwise:YES];
                arc.lineWidth = 3; arc.lineCapStyle = NSLineCapStyleRound;
                [color setStroke]; [arc stroke];
            }
            [shortLabel drawAtPoint:NSMakePoint(left + 26, 16) withAttributes:caption];
            [percent drawAtPoint:NSMakePoint(left + 26, 3) withAttributes:number];
        } else {
            [label drawAtPoint:NSMakePoint(left, 15) withAttributes:caption];
            CGFloat numberWidth = [percent sizeWithAttributes:number].width;
            [percent drawAtPoint:NSMakePoint(left + width - numberWidth, 14) withAttributes:number];
            NSRect track = NSMakeRect(left, 5, width, 4);
            [[NSColor colorWithWhite:0.23 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:track xRadius:2 yRadius:2] fill];
            if (remaining > 0) {
                NSRect fill = track; fill.size.width *= remaining / 100.0;
                [color setFill]; [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:2 yRadius:2] fill];
            }
        }
    }
}
@end

static NSButton *MakeTrayButton(id target) {
    NSButton *button = [NSButton buttonWithTitle:@"" target:target action:@selector(showDetails:)];
    button.bordered = NO;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleNone;
    [button.widthAnchor constraintEqualToConstant:54].active = YES;
    [button.heightAnchor constraintEqualToConstant:30].active = YES;
    [button setAccessibilityLabel:L(@"Остаток лимитов Codex: 5 часов и неделя")];
    return button;
}

@interface Helper : NSObject <NSApplicationDelegate, NSTouchBarDelegate>
@property NSStatusItem *status;
@property NSCustomTouchBarItem *tray;
@property NSButton *trayButton;
@property QuotaView *quotaView;
@property QuotaView *detailView;
@property NSInteger displayStyle;
@property NSArray<NSMenuItem *> *styleItems;
@property NSTouchBar *detailBar;
@property NSUInteger detailRequests;
@property NSButton *fiveButton;
@property NSButton *weekButton;
@property NSMenuItem *fiveMenu;
@property NSMenuItem *weekMenu;
@property NSMenuItem *messageMenu;
@property NSDictionary *windows;
@property NSDate *lastUpdate;
@property NSString *problem;
@property NSString *cliPath;
@property NSTask *server;
@property NSFileHandle *input;
@property NSMutableData *buffer;
@property NSTimer *timer;
@property BOOL visible;
@property BOOL ready;
@property BOOL busy;
@property BOOL stopping;
@property BOOL traySupported;
@property BOOL trayRegistered;
@property BOOL detailVisible;
@property NSInteger nextID;
@property NSInteger pendingID;
@property NSInteger generation;
@property void (*setPresence)(NSString *, BOOL);
@end

@implementation Helper
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.nextID = 10;
    self.windows = @{};
    self.problem = @"Подключение…";
    NSInteger savedStyle = [NSUserDefaults.standardUserDefaults integerForKey:@"displayStyle"];
    self.displayStyle = (savedStyle >= 0 && savedStyle <= 2) ? savedStyle : 0;
    self.status = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    [self configureMenu];
    self.status.visible = NO;

    void *framework = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY);
    self.setPresence = framework ? dlsym(framework, "DFRElementSetControlStripPresenceForIdentifier") : NULL;
    self.traySupported = self.setPresence && [NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)] && [NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)];
    if (self.traySupported) {
        self.tray = [[NSCustomTouchBarItem alloc] initWithIdentifier:TrayID];
        self.quotaView = [[QuotaView alloc] initWithFrame:NSMakeRect(0, 0, 54, 30)];
        self.quotaView.fiveRemaining = -1; self.quotaView.weekRemaining = -1;
        self.quotaView.compact = YES;
        // Touch Bar dispatches taps through native controls, not mouseDown on a plain view.
        self.trayButton = MakeTrayButton(self);
        self.tray.view = self.trayButton;
        self.detailView = [[QuotaView alloc] initWithFrame:NSMakeRect(0, 0, 360, 30)];
    }
    self.detailBar = [NSTouchBar new];
    self.detailBar.delegate = self;
    self.detailBar.defaultItemIdentifiers = @[@"gauges", @"refresh", @"close"];

    NSNotificationCenter *nc = NSWorkspace.sharedWorkspace.notificationCenter;
    [nc addObserver:self selector:@selector(workspaceChanged:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
    [nc addObserver:self selector:@selector(workspaceChanged:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
    [nc addObserver:self selector:@selector(woke:) name:NSWorkspaceDidWakeNotification object:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [self syncVisibility];
}
- (void)configureMenu {
    NSMenu *menu = [NSMenu new];
    self.fiveMenu = [menu addItemWithTitle:L(@"5 часов: —") action:nil keyEquivalent:@""];
    self.weekMenu = [menu addItemWithTitle:L(@"Неделя: —") action:nil keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    self.messageMenu = [menu addItemWithTitle:L(@"Подключение…") action:nil keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *refresh = [menu addItemWithTitle:L(@"Обновить сейчас") action:@selector(refresh:) keyEquivalent:@"r"];
    refresh.target = self;
    NSMenuItem *touch = [menu addItemWithTitle:L(@"Показать лимиты на Touch Bar") action:@selector(showDetails:) keyEquivalent:@""];
    touch.target = self;
    NSMenuItem *appearance = [menu addItemWithTitle:L(@"Оформление") action:nil keyEquivalent:@""];
    NSMenu *styles = [NSMenu new];
    NSMutableArray *styleItems = [NSMutableArray array];
    NSArray *styleNames = @[L(@"Полоски прогресса"), L(@"Компактные проценты"), L(@"Кольца")];
    for (NSInteger i = 0; i < 3; ++i) {
        NSMenuItem *choice = [styles addItemWithTitle:styleNames[i] action:@selector(changeStyle:) keyEquivalent:@""];
        choice.tag = i; choice.target = self;
        choice.state = i == self.displayStyle ? NSControlStateValueOn : NSControlStateValueOff;
        [styleItems addObject:choice];
    }
    self.styleItems = styleItems;
    appearance.submenu = styles;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [menu addItemWithTitle:L(@"Выключить помощник") action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    NSMenuItem *language = [menu addItemWithTitle:@"Language / Язык" action:nil keyEquivalent:@""];
    NSMenu *languages = [NSMenu new];
    NSArray *codes = @[@"system", @"en", @"ru"];
    NSArray *names = @[@"System / Как в macOS", @"English", @"Русский"];
    NSString *selected = [NSUserDefaults.standardUserDefaults stringForKey:@"interfaceLanguage"] ?: @"system";
    for (NSUInteger i = 0; i < codes.count; ++i) {
        NSMenuItem *choice = [languages addItemWithTitle:names[i] action:@selector(changeLanguage:) keyEquivalent:@""];
        choice.target = self; choice.representedObject = codes[i];
        choice.state = [selected isEqualToString:codes[i]] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    language.submenu = languages;
    self.status.menu = menu;
}
- (void)changeLanguage:(NSMenuItem *)item {
    [NSUserDefaults.standardUserDefaults setObject:item.representedObject forKey:@"interfaceLanguage"];
    [self closeDetails:nil];
    [self configureMenu];
    self.detailBar = [NSTouchBar new];
    self.detailBar.delegate = self;
    self.detailBar.defaultItemIdentifiers = @[@"gauges", @"refresh", @"close"];
    [self.trayButton setAccessibilityLabel:L(@"Остаток лимитов Codex: 5 часов и неделя")];
    [self render];
}
- (BOOL)chatGPTRunning {
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
        if ([@[@"com.openai.codex", @"com.openai.chat"] containsObject:app.bundleIdentifier ?: @""]) return YES;
    }
    return NO;
}
- (void)workspaceChanged:(NSNotification *)note { [self syncVisibility]; }
- (void)changeStyle:(NSMenuItem *)item {
    self.displayStyle = item.tag;
    [NSUserDefaults.standardUserDefaults setInteger:self.displayStyle forKey:@"displayStyle"];
    for (NSMenuItem *choice in self.styleItems) choice.state = choice.tag == self.displayStyle ? NSControlStateValueOn : NSControlStateValueOff;
    [self render];
}
- (void)woke:(NSNotification *)note {
    [self syncVisibility];
    if (self.visible) { [self stopServer]; [self startServer]; }
}
- (void)syncVisibility {
    BOOL show = [self chatGPTRunning];
    if (show == self.visible) return;
    self.visible = show;
    self.status.visible = show;
    if (self.traySupported) {
        if (show) {
            [NSTouchBarItem addSystemTrayItem:self.tray];
            self.setPresence(TrayID, YES);
            self.trayRegistered = YES;
        } else {
            [self closeDetails:nil];
            self.setPresence(TrayID, NO);
            [NSTouchBarItem removeSystemTrayItem:self.tray];
            self.trayRegistered = NO;
        }
    }
    if (show) [self startServer]; else [self stopServer];
    [self render];
}
- (NSString *)findCLI {
    NSArray *paths = @[@"/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", @"/Applications/Codex.app/Contents/Resources/codex", @"/opt/homebrew/bin/codex", @"/usr/local/bin/codex"];
    for (NSString *path in paths) if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    return nil;
}
- (void)send:(NSDictionary *)message {
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (!data || !self.input) return;
    NSMutableData *line = [data mutableCopy];
    [line appendBytes:"\n" length:1];
    @try { [self.input writeData:line]; }
    @catch (NSException *exception) { self.problem = @"Соединение прервано"; [self stopServer]; [self render]; }
}
- (void)startServer {
    if (self.server || !self.visible || self.stopping) return;
    self.cliPath = [self findCLI];
    if (!self.cliPath) { self.problem = @"Codex CLI не найден. Откройте ChatGPT."; [self render]; return; }
    self.problem = @"Подключение…";
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:self.cliPath];
    task.arguments = @[@"app-server", @"--stdio"];
    // No turns, prompts, threads or model requests are created by this helper.
    NSPipe *inPipe = [NSPipe pipe], *outPipe = [NSPipe pipe];
    task.standardInput = inPipe;
    task.standardOutput = outPipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    self.input = inPipe.fileHandleForWriting;
    self.buffer = [NSMutableData new];
    self.server = task;
    NSInteger generation = ++self.generation;
    __weak Helper *weakSelf = self;
    outPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *chunk = handle.availableData;
        if (!chunk.length) { handle.readabilityHandler = nil; return; }
        dispatch_async(dispatch_get_main_queue(), ^{
            Helper *s = weakSelf;
            if (!s || s.generation != generation) return;
            [s.buffer appendData:chunk];
            // Bound the buffer even if a future server emits unexpected output.
            if (s.buffer.length > 4 * 1024 * 1024) { s.problem = @"Некорректный ответ CLI"; [s stopServer]; [s render]; return; }
            NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
            while (YES) {
                NSRange range = [s.buffer rangeOfData:newline options:0 range:NSMakeRange(0, s.buffer.length)];
                if (range.location == NSNotFound) break;
                NSData *line = [s.buffer subdataWithRange:NSMakeRange(0, range.location)];
                [s.buffer replaceBytesInRange:NSMakeRange(0, range.location + 1) withBytes:NULL length:0];
                id value = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
                if ([value isKindOfClass:NSDictionary.class]) [s receive:value];
                if (s.generation != generation) break;
            }
        });
    };
    task.terminationHandler = ^(NSTask *ended) {
        outPipe.fileHandleForReading.readabilityHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            Helper *s = weakSelf;
            if (!s || s.generation != generation) return;
            s.server = nil; s.input = nil; s.ready = NO; s.busy = NO;
            s.problem = @"CLI недоступен. Повтор через 30 секунд.";
            [s render];
        });
    };
    NSError *error;
    if (![task launchAndReturnError:&error]) {
        outPipe.fileHandleForReading.readabilityHandler = nil;
        self.server = nil; self.input = nil;
        self.problem = @"Не удалось запустить CLI";
        [self render]; return;
    }
    [self send:@{@"id": @1, @"method": @"initialize", @"params": @{@"clientInfo": @{@"name": @"codex_touchbar", @"title": @"Codex Touch Bar", @"version": @"1.2.0"}}}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        Helper *s = weakSelf;
        if (s && s.generation == generation && !s.ready) { s.problem = @"Время подключения истекло"; [s stopServer]; [s render]; }
    });
    [self render];
}
- (void)receive:(NSDictionary *)message {
    NSNumber *requestID = [message[@"id"] isKindOfClass:NSNumber.class] ? message[@"id"] : nil;
    if (requestID.integerValue == 1) {
        if (message[@"error"]) { self.problem = @"CLI не поддерживает подключение"; [self stopServer]; [self render]; return; }
        self.ready = YES;
        [self send:@{@"method": @"initialized"}];
        [self refresh:nil];
        return;
    }
    if (requestID && requestID.integerValue == self.pendingID) {
        self.busy = NO;
        if (message[@"error"]) {
            NSString *msg = [message[@"error"] isKindOfClass:NSDictionary.class] ? message[@"error"][@"message"] : nil;
            self.problem = [msg isKindOfClass:NSString.class] ? msg : @"Не удалось получить лимиты";
            [self render];
        } else if ([message[@"result"] isKindOfClass:NSDictionary.class]) [self applyResult:message[@"result"]];
        return;
    }
    // Notifications may carry only one quota window. Fetch the complete snapshot.
    if ([message[@"method"] isEqual:@"account/rateLimits/updated"]) [self refresh:nil];
}
- (void)applyResult:(NSDictionary *)result {
    self.windows = Windows(result);
    self.lastUpdate = [NSDate date];
    self.problem = self.windows.count ? nil : @"Сервис не вернул окна 5 часов / 7 дней";
    [self render];
}
- (void)refresh:(id)sender {
    if (!self.visible) return;
    if (!self.server) { [self startServer]; return; }
    if (!self.ready || self.busy) return;
    self.busy = YES;
    self.pendingID = ++self.nextID;
    NSInteger requestID = self.pendingID, generation = self.generation;
    [self send:@{@"id": @(requestID), @"method": @"account/rateLimits/read"}];
    __weak Helper *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        Helper *s = weakSelf;
        if (s && s.generation == generation && s.busy && s.pendingID == requestID) {
            s.problem = @"Сервис не ответил. Повтор через 30 секунд.";
            [s stopServer]; [s render];
        }
    });
}
- (void)tick:(id)sender {
    [self syncVisibility];
    // Reassert the System Preferences Control Strip setting after macOS has
    // rebuilt its customization palette. This does not add duplicate items.
    if (self.visible && self.traySupported && self.trayRegistered) self.setPresence(TrayID, YES);
    [self render]; [self refresh:nil];
}
- (void)stopServer {
    ++self.generation;
    NSTask *task = self.server;
    self.server = nil; self.input = nil; self.ready = NO; self.busy = NO;
    if (task.running) {
        [task terminate];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (task.running) kill(task.processIdentifier, SIGKILL);
        });
    }
}
- (void)render {
    NSDate *now = [NSDate date];
    BOOL stale = !self.lastUpdate || [now timeIntervalSinceDate:self.lastUpdate] > 180;
    // After an error, never present cached values as a current successful reading.
    BOOL unavailable = stale || self.problem.length;
    NSString *five = unavailable ? @"—" : Percent(self.windows[@"five"], now);
    NSString *week = unavailable ? @"—" : Percent(self.windows[@"week"], now);
    NSString *title = [NSString stringWithFormat:L(@"5ч %@ · 7д %@"), five, week];
    self.status.button.title = [@"CX " stringByAppendingString:title];
    self.fiveButton.title = [NSString stringWithFormat:L(@"5 часов: %@ · ↻ %@"), five, Countdown(self.windows[@"five"])];
    self.weekButton.title = [NSString stringWithFormat:L(@"Неделя: %@ · ↻ %@"), week, Countdown(self.windows[@"week"])];
    self.quotaView.style = self.displayStyle;
    double fiveValue = ([five isEqual:@"—"] || !self.windows[@"five"]) ? -1 : fmax(0, fmin(100, 100 - [self.windows[@"five"][@"usedPercent"] doubleValue]));
    double weekValue = ([week isEqual:@"—"] || !self.windows[@"week"]) ? -1 : fmax(0, fmin(100, 100 - [self.windows[@"week"][@"usedPercent"] doubleValue]));
    self.quotaView.fiveRemaining = fiveValue; self.quotaView.weekRemaining = weekValue;
    self.detailView.style = self.displayStyle;
    self.detailView.fiveRemaining = fiveValue; self.detailView.weekRemaining = weekValue;
    self.quotaView.needsDisplay = YES;
    if (self.trayButton) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(54, 30)];
        [image lockFocus];
        [self.quotaView drawRect:self.quotaView.bounds];
        [image unlockFocus];
        self.trayButton.image = image;
        [self.trayButton setAccessibilityValue:title];
    }
    self.detailView.needsDisplay = YES;
    [self.quotaView setAccessibilityValue:title];
    self.fiveMenu.title = [NSString stringWithFormat:L(@"5 часов: осталось %@ · сброс %@"), five, ResetText(self.windows[@"five"])];
    self.weekMenu.title = [NSString stringWithFormat:L(@"Неделя: осталось %@ · сброс %@"), week, ResetText(self.windows[@"week"])];
    NSString *message = L(self.problem) ?: (stale ? L(@"Данные устарели, обновляю…") : L(@"Автообновление каждые 30 секунд"));
    if (!self.traySupported) message = [message stringByAppendingString:L(@" · Touch Bar API недоступен")];
    self.messageMenu.title = message;
    self.status.button.toolTip = [NSString stringWithFormat:@"%@\n%@\n%@", self.fiveMenu.title, self.weekMenu.title, message];
    self.quotaView.toolTip = self.status.button.toolTip;
    BOOL low = NO;
    if (!unavailable) for (NSDictionary *w in self.windows.allValues) {
        if ([w[@"resetsAt"] doubleValue] > now.timeIntervalSince1970 && 100 - [w[@"usedPercent"] doubleValue] <= 15) low = YES;
    }
    if (self.fiveButton) self.fiveButton.bezelColor = low ? NSColor.systemRedColor : NSColor.controlColor;
    if (self.weekButton) self.weekButton.bezelColor = low ? NSColor.systemRedColor : NSColor.controlColor;
    // Diagnostic contains percentages and availability only, never credentials or server output.
    NSDictionary *state = @{@"version": NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"development", @"refreshIntervalSeconds": @30, @"detailRequests": @(self.detailRequests), @"visible": @(self.visible), @"touchBarAPI": @(self.traySupported), @"trayRegistered": @(self.trayRegistered), @"displayStyle": @(self.displayStyle), @"language": InterfaceLanguage(), @"fiveRemaining": five, @"weekRemaining": week, @"status": message, @"updatedAt": @(self.lastUpdate.timeIntervalSince1970)};
    NSData *json = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:nil];
    NSString *statePath = [NSBundle.mainBundle.bundlePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"CodexTouchBar-status.json"];
    [json writeToFile:statePath options:NSDataWritingAtomic error:nil];
}
- (NSTouchBarItem *)touchBar:(NSTouchBar *)bar makeItemForIdentifier:(NSString *)identifier {
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    if ([identifier isEqual:@"gauges"]) {
        self.detailView.compact = NO;
        item.view = self.detailView;
    }
    else if ([identifier isEqual:@"refresh"]) item.view = [NSButton buttonWithTitle:L(@"Обновить") target:self action:@selector(refresh:)];
    else item.view = [NSButton buttonWithTitle:L(@"Закрыть") target:self action:@selector(closeDetails:)];
    [self render];
    return item;
}
- (void)showDetails:(id)sender {
    self.detailRequests++;
    if ([NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:systemTrayItemIdentifier:)]) {
        [NSTouchBar presentSystemModalTouchBar:self.detailBar systemTrayItemIdentifier:TrayID];
    } else if ([NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]) {
        [NSTouchBar presentSystemModalTouchBar:self.detailBar placement:0 systemTrayItemIdentifier:TrayID];
    } else {
        self.problem = @"Подробная панель Touch Bar недоступна";
        [self render];
        return;
    }
    self.detailVisible = YES;
    [self render];
}
- (void)closeDetails:(id)sender {
    if (self.detailVisible && [NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]) [NSTouchBar dismissSystemModalTouchBar:self.detailBar];
    self.detailVisible = NO;
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)note {
    self.stopping = YES;
    [self.timer invalidate];
    [self stopServer];
    [self closeDetails:nil];
    if (self.trayRegistered) { self.setPresence(TrayID, NO); [NSTouchBarItem removeSystemTrayItem:self.tray]; }
}
@end

static int SelfTest(void) {
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1000];
    NSDictionary *five = @{@"usedPercent": @15, @"windowDurationMins": @300, @"resetsAt": @2000};
    NSDictionary *week = @{@"usedPercent": @29, @"windowDurationMins": @10080, @"resetsAt": @3000};
    NSDictionary *r = @{@"rateLimitsByLimitId": @{@"codex": @{@"primary": week, @"secondary": five}, @"other": @{@"primary": five}}};
    NSDictionary *w = Windows(r);
    NSCAssert([Percent(w[@"five"], now) isEqual:@"85%"] && [Percent(w[@"week"], now) isEqual:@"71%"], @"Duration-based mapping, not field order");
    NSCAssert(Windows(@{@"rateLimits": @{@"limitId": @"codex", @"primary": five, @"secondary": NSNull.null}}).count == 1, @"Missing secondary must stay unavailable");
    NSCAssert(Windows(@{@"rateLimits": @{@"limitId": @"other", @"primary": five}}).count == 0, @"Do not substitute another bucket");
    NSCAssert(Windows(@{@"rateLimits": @{@"primary": @{@"windowDurationMins": @300, @"usedPercent": NSNull.null, @"resetsAt": @2000}}}).count == 0, @"Null must not read as zero used");
    NSCAssert([Percent(five, [NSDate dateWithTimeIntervalSince1970:2001]) isEqual:@"—"], @"Expired reading must not imply reset");
    NSCAssert([Percent(@{@"usedPercent": @110, @"resetsAt": @2000}, now) isEqual:@"0%"], @"Clamp exhausted quota");
    QuotaView *compact = [[QuotaView alloc] initWithFrame:NSZeroRect];
    compact.compact = YES;
    NSCAssert(NSEqualSizes(compact.intrinsicContentSize, NSMakeSize(54, 30)), @"Control Strip item must fit the narrow slot");
    compact.compact = NO;
    NSCAssert(NSEqualSizes(compact.intrinsicContentSize, NSMakeSize(360, 30)), @"Expanded gauges must use a full-width view");
    NSDictionary *savedArguments = [NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain];
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"interfaceLanguage": @"en"} forName:NSArgumentDomain];
    NSCAssert([L(@"Оформление") isEqualToString:@"Appearance"] && [L(@"5ч") isEqualToString:@"5h"], @"English menu and gauge labels");
    NSCAssert([ResetText(five) containsString:@"Jan"], @"Reset dates must follow the selected English language");
    NSCAssert([L(@"Автообновление каждые 30 секунд") isEqualToString:@"Refreshes every 30 seconds"], @"English refresh status");
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"interfaceLanguage": @"ru"} forName:NSArgumentDomain];
    NSCAssert([L(@"Оформление") isEqualToString:@"Оформление"], @"Russian language switch");
    [NSUserDefaults.standardUserDefaults setVolatileDomain:savedArguments forName:NSArgumentDomain];
    puts("PASS: quota mapping, missing/null data, foreign bucket, expired data, exhaustion, Control Strip sizing, English/Russian");
    return 0;
}
static int Preview(const char *path) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:736 pixelsHigh:120 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    NSAffineTransform *scale = [NSAffineTransform transform]; [scale scaleBy:4]; [scale concat];
    QuotaView *view = [[QuotaView alloc] initWithFrame:NSMakeRect(0, 0, 184, 30)];
    view.fiveRemaining = 82; view.weekRemaining = 30; view.style = 0;
    [view drawRect:view.bounds];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:[NSString stringWithUTF8String:path] atomically:YES] ? 0 : 1;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) return SelfTest();
        if (argc > 2 && strcmp(argv[1], "--preview") == 0) return Preview(argv[2]);
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        Helper *helper = [Helper new];
        app.delegate = helper;
        [app run];
    }
    return 0;
}
