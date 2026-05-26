//
//  ProjectListView.swift
//  DevCal
//
//  Top-level list of all projects with search, sort, and a free-tier upsell when
//  the user tries to add a second project on the Free plan.
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct ProjectListView: View {
    @Environment(\.projectRepository) private var projectRepository
    @Environment(Entitlements.self) private var entitlements
    @Query(
        sort: [
            SortDescriptor(\Project.sortIndex),
            SortDescriptor(\Project.createdAt, order: .reverse)
        ]
    ) private var projects: [Project]

    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var showAddProject = false
    @State private var showPaywall = false
    @State private var bannerHeight: CGFloat = 0
    @State private var editingProject: Project?
    @State private var pendingDelete: Project?
    @State private var showDeleteConfirm = false
    @State private var listError: String? = nil
    @State private var showErrorAlert = false

    var body: some View {
        Group {
            if projects.isEmpty {
                emptyState
            } else {
                list
                    .contentMargins(.top, entitlements.isPro ? 0 : bannerHeight + 8, for: .scrollContent)
                    .overlay(alignment: .top) {
                        if !entitlements.isPro {
                            freeTierBanner
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { newValue in
                                    bannerHeight = newValue
                                }
                        }
                    }
            }
        }
        .background(Theme.appBackground)
        .navigationTitle("Projects")
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .toolbar, prompt: Text("Search"))
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if #available(iOS 26.0, *) {
                    Button {
                        addOrUpsell()
                    } label: {
                        Image(ph: "plus")
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Theme.onTint)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                } else {
                    Button {
                        addOrUpsell()
                    } label: {
                        Image(ph: "plus")
                            .frame(width: 18, height: 18)
                    }
                }
            }
        }
        .onChange(of: isSearchPresented) { _, isPresented in
            if !isPresented {
                searchText = ""
            }
        }
        .sheet(isPresented: $showAddProject) {
            NavigationStack {
                AddProjectView()
            }
        }
        .sheet(item: $editingProject) { project in
            NavigationStack {
                AddProjectView(editing: project)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
        .systemAlert(
            "確定要刪除專案？",
            isPresented: $showDeleteConfirm
        ) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("刪除", role: .destructive) {
                if let project = pendingDelete {
                    Task { await runDelete(project) }
                }
                pendingDelete = nil
            }
        } message: {
            Text("此專案的所有支出與收入記錄將一併刪除，且無法復原。")
        }
        .systemAlert("Operation failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { listError = nil }
        } message: {
            Text(listError ?? "")
        }
    }

    private func runDelete(_ project: Project) async {
        guard let repo = projectRepository else { return }
        do {
            try await repo.deleteProject(project)
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        listError = error.localizedDescription
        showErrorAlert = true
    }

    private func addOrUpsell() {
        if canCreateMore {
            showAddProject = true
        } else {
            showPaywall = true
        }
    }

    // MARK: - States

    private var canCreateMore: Bool {
        entitlements.isPro || projects.count < entitlements.freeProjectLimit
    }

    private var filtered: [Project] {
        if searchText.isEmpty { return projects }
        let lower = searchText.lowercased()
        return projects.filter {
            $0.name.lowercased().contains(lower) ||
            $0.projectDescription.lowercased().contains(lower)
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { project in
                ZStack {
                    NavigationLink(value: project) {
                        EmptyView()
                    }
                    .opacity(0)

                    VStack(spacing: 0) {
                        ProjectCard(project: project)
                            .contextMenu {
                                Button("編輯") {
                                    editingProject = project
                                }
                                Button("刪除", role: .destructive) {
                                    pendingDelete = project
                                    showDeleteConfirm = true
                                }
                            }
                        if project.id != filtered.last?.id {
                            rowDivider
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .onMove(perform: handleMove)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.appBackground)
        .navigationDestination(for: Project.self) { project in
            ProjectDashboardView(project: project)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    /// Renumbers every project's `sortIndex` by its new visible position.
    /// Skipped while the user is searching — the filtered indices wouldn't
    /// map cleanly back to the full project array.
    private func handleMove(_ from: IndexSet, _ to: Int) {
        guard searchText.isEmpty, let repo = projectRepository else { return }
        var items = projects
        items.move(fromOffsets: from, toOffset: to)
        Task {
            do {
                try await repo.reorder(items)
            } catch {
                present(error)
            }
        }
    }

    private var emptyState: some View {
        // No CTA button — the toolbar `+` already drives "add first project",
        // and a second CTA in the empty state just clutters the screen.
        ContentUnavailableView {
            Label("No projects yet", phImage: "stack")
        } description: {
            Text("Create your first project to start tracking revenue, expenses, and break-even progress.")
        }
    }

    private var freeTierBanner: some View {
        HStack(spacing: 12) {
            Image(ph: "sparkle")
                .frame(width: 22, height: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Free plan: \(projects.count)/\(entitlements.freeProjectLimit) project")
                    .appFont(.subheadline, weight: .semibold)
                Text("Upgrade to Pro for unlimited projects.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            upgradePillButton
        }
        .padding(16)
        .bannerStyle()
    }

    private var upgradePillButton: some View {
        Button {
            showPaywall = true
        } label: {
            Text("Upgrade")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(Theme.brand)
        }
        .buttonStyle(.plain)
    }
}

