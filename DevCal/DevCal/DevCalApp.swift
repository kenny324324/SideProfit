//
//  DevCalApp.swift
//  DevCal
//
//  Created by Kenny on 2026/5/12.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct DevCalApp: App {
    @AppStorage("needsOnboarding") private var needsOnboarding = false
    @AppStorage("preferredAppearance") private var preferredAppearance: String = "system"
    @AppStorage(Typography.DefaultsKey.latinMode) private var latinMode: String = Typography.FontMode.branded.rawValue
    @AppStorage(Typography.DefaultsKey.cjkMode) private var cjkMode: String = Typography.FontMode.native.rawValue
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"
    @Environment(\.scenePhase) private var scenePhase
    // Built in `init()` *after* FirebaseApp.configure() so the auth state
    // listener has a configured Firebase app to attach to.
    @State private var auth: AuthService
    @State private var entitlements = Entitlements()
    @State private var fx = ExchangeRateService.shared
    @State private var appReviewPrompter = AppReviewPrompter()
    @State private var showSplash = true
    // Data layer: FirestoreSyncService owns the on-disk push queue + (in
    // Step 3+) drives push/pull. Held as a single instance so background
    // work and the UI agree on `status`.
    @State private var syncService: FirestoreSyncService
    @State private var projectRepository: ProjectRepository
    @State private var transactionRepository: TransactionRepository
    @State private var timeLogRepository: TimeLogRepository
    @State private var categoryItemRepository: CategoryItemRepository
    @State private var milestoneRepository: MilestoneRepository
    @State private var transactionUseCase: TransactionUseCase
    #if DEBUG
    @AppStorage("splashPreviewTrigger") private var splashPreviewTrigger: Int = 0
    #endif

    private let container: ModelContainer

    init() {
        // Firebase first so AuthService's state listener (constructed below
        // via the @State default) has a configured app to talk to. Phase 1
        // wires only FirebaseAuth; Firestore / Crashlytics / etc. are added
        // in later phases.
        FirebaseApp.configure()
        _auth = State(initialValue: AuthService())
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
        let initialSync = FirestoreSyncService()
        let projectRepo = ProjectRepository(context: context, sync: initialSync)
        let txnRepo = TransactionRepository(context: context, sync: initialSync)
        let timeLogRepo = TimeLogRepository(context: context, sync: initialSync)
        let categoryRepo = CategoryItemRepository(context: context, sync: initialSync)
        let milestoneRepo = MilestoneRepository(context: context, sync: initialSync)
        let useCase = TransactionUseCase(
            context: context,
            transactionRepository: txnRepo,
            categoryItemRepository: categoryRepo,
            sync: initialSync
        )
        _syncService = State(initialValue: initialSync)
        _projectRepository = State(initialValue: projectRepo)
        _transactionRepository = State(initialValue: txnRepo)
        _timeLogRepository = State(initialValue: timeLogRepo)
        _categoryItemRepository = State(initialValue: categoryRepo)
        _milestoneRepository = State(initialValue: milestoneRepo)
        _transactionUseCase = State(initialValue: useCase)

        Task { @MainActor [initialSync] in
            SeedData.seedIfEmpty(resolvedContainer.mainContext)
            // First scheduler pass uses the user's display currency for
            // break-even stamping; FX may be cold but stamping is
            // best-effort anyway.
            let displayCurrency = UserDefaults.standard.string(forKey: "defaultCurrency") ?? "TWD"
            do {
                try SubscriptionScheduler.runDueCheck(
                    context: resolvedContainer.mainContext,
                    sync: initialSync,
                    displayCurrency: displayCurrency,
                    fx: ExchangeRateService.shared
                )
            } catch {
                #if DEBUG
                print("[scheduler] launch run failed: \(error)")
                #endif
            }
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
                    .environment(\.milestoneRepository, milestoneRepository)
                    .environment(\.transactionUseCase, transactionUseCase)
                    .environment(\.syncService, syncService)
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
                do {
                    try SubscriptionScheduler.runDueCheck(
                        context: container.mainContext,
                        sync: syncService,
                        displayCurrency: defaultCurrency,
                        fx: fx
                    )
                } catch {
                    #if DEBUG
                    print("[scheduler] scenePhase run failed: \(error)")
                    #endif
                }
                Task { await fx.refreshIfNeeded() }
            }
        }
        .onChange(of: latinMode) { _, _ in Typography.applyUIKitAppearance() }
        .onChange(of: cjkMode) { _, _ in Typography.applyUIKitAppearance() }
        .onChange(of: auth.account?.id) { _, _ in
            // Sync engine derives `.disabled` / `.idle` from auth, so any
            // sign-in or sign-out has to feed that state machine.
            syncService.refreshStatusFromAuth()
        }
    }

    private var colorScheme: ColorScheme? {
        switch preferredAppearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
