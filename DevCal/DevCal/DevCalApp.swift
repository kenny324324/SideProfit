//
//  DevCalApp.swift
//  DevCal
//
//  Created by Kenny on 2026/5/12.
//

import SwiftUI
import SwiftData

@main
struct DevCalApp: App {
    @AppStorage("needsOnboarding") private var needsOnboarding = false
    @AppStorage("preferredAppearance") private var preferredAppearance: String = "system"
    @AppStorage(Typography.DefaultsKey.latinMode) private var latinMode: String = Typography.FontMode.branded.rawValue
    @AppStorage(Typography.DefaultsKey.cjkMode) private var cjkMode: String = Typography.FontMode.native.rawValue
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = AuthService()
    @State private var entitlements = Entitlements()
    @State private var fx = ExchangeRateService.shared
    @State private var appReviewPrompter = AppReviewPrompter()
    @State private var showSplash = true
    // Data layer: a NoopSyncService stands in for Phase-4 Firestore so views
    // can already depend on the repository / sync API. Held as a single
    // instance so background work and the UI agree on `status`.
    @State private var syncService: NoopSyncService = NoopSyncService()
    @State private var projectRepository: ProjectRepository
    @State private var transactionRepository: TransactionRepository
    @State private var timeLogRepository: TimeLogRepository
    @State private var categoryItemRepository: CategoryItemRepository
    @State private var transactionUseCase: TransactionUseCase
    #if DEBUG
    @AppStorage("splashPreviewTrigger") private var splashPreviewTrigger: Int = 0
    #endif

    private let container: ModelContainer

    init() {
        Typography.applyUIKitAppearance()
        // First-launch default: track the device locale so non-Taiwan users
        // open the app in their own currency. Subsequent launches respect
        // whatever the user picked in Settings.
        if UserDefaults.standard.object(forKey: "defaultCurrency") == nil {
            let locale = Locale.current.currency?.identifier ?? "TWD"
            let supported = ExchangeRateService.supportedCodes
            UserDefaults.standard.set(supported.contains(locale) ? locale : "TWD",
                                      forKey: "defaultCurrency")
        }

        let schema = Schema([
            Project.self,
            Transaction.self,
            TimeLog.self,
            Milestone.self,
            CategoryItem.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let resolvedContainer: ModelContainer
        do {
            resolvedContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
        self.container = resolvedContainer

        // App.init runs on the main actor (SwiftUI App is @MainActor), so
        // mainContext / repository ctors are safe to call synchronously here.
        let context = resolvedContainer.mainContext
        let initialSync = NoopSyncService()
        let projectRepo = ProjectRepository(context: context, sync: initialSync)
        let txnRepo = TransactionRepository(context: context, sync: initialSync)
        let timeLogRepo = TimeLogRepository(context: context, sync: initialSync)
        let categoryRepo = CategoryItemRepository(context: context, sync: initialSync)
        let useCase = TransactionUseCase(
            context: context,
            transactionRepository: txnRepo,
            categoryItemRepository: categoryRepo
        )
        _syncService = State(initialValue: initialSync)
        _projectRepository = State(initialValue: projectRepo)
        _transactionRepository = State(initialValue: txnRepo)
        _timeLogRepository = State(initialValue: timeLogRepo)
        _categoryItemRepository = State(initialValue: categoryRepo)
        _transactionUseCase = State(initialValue: useCase)

        Task { @MainActor in
            SeedData.seedIfEmpty(resolvedContainer.mainContext)
            // First scheduler pass uses the user's display currency for
            // break-even stamping; FX may be cold but stamping is
            // best-effort anyway.
            let displayCurrency = UserDefaults.standard.string(forKey: "defaultCurrency") ?? "TWD"
            SubscriptionScheduler.runDueCheck(
                context: resolvedContainer.mainContext,
                displayCurrency: displayCurrency,
                fx: ExchangeRateService.shared
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(auth)
                    .environment(entitlements)
                    .environment(fx)
                    .environment(appReviewPrompter)
                    .environment(\.projectRepository, projectRepository)
                    .environment(\.transactionRepository, transactionRepository)
                    .environment(\.timeLogRepository, timeLogRepository)
                    .environment(\.categoryItemRepository, categoryItemRepository)
                    .environment(\.transactionUseCase, transactionUseCase)
                    .dismissKeyboardOnTapOutside()
                    .inAppBrowser()
                    .appReviewPrompt(appReviewPrompter)
                    .fullScreenCover(isPresented: $needsOnboarding) {
                        SWOnboardingView {
                            needsOnboarding = false
                        }
                    }
                    // Force a full hierarchy rebuild when the font mode flips,
                    // so cached `.appFont(...)` resolutions get reissued.
                    .id("\(latinMode)-\(cjkMode)")

                if showSplash {
                    SplashView()
                        .transition(.opacity.animation(.easeInOut(duration: SplashDefaults.fadeOutDuration)))
                        .zIndex(1)
                        .task(id: showSplash) {
                            try? await Task.sleep(for: SplashDefaults.minDisplayDuration)
                            withAnimation(.easeInOut(duration: SplashDefaults.fadeOutDuration)) {
                                showSplash = false
                            }
                        }
                }
            }
            .preferredColorScheme(colorScheme)
            .task {
                // Pull fresh rates on launch if the cache is older than 6h.
                await fx.refreshIfNeeded()
            }
            #if DEBUG
            .onChange(of: splashPreviewTrigger) { _, _ in
                guard !showSplash else { return }
                showSplash = true
            }
            #endif
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                SubscriptionScheduler.runDueCheck(
                    context: container.mainContext,
                    displayCurrency: defaultCurrency,
                    fx: fx
                )
                Task { await fx.refreshIfNeeded() }
            }
        }
        .onChange(of: latinMode) { _, _ in Typography.applyUIKitAppearance() }
        .onChange(of: cjkMode) { _, _ in Typography.applyUIKitAppearance() }
    }

    private var colorScheme: ColorScheme? {
        switch preferredAppearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
