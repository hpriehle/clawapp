import SwiftUI
import Combine
import SharedModels

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var items: [DashboardItemDTO] = []
    @State private var isLoading = true
    @State private var isEditing = false
    @State private var showLibrary = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.md),
        GridItem(.flexible(), spacing: Theme.Spacing.md),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(Theme.Colors.accent)
                } else if items.isEmpty {
                    emptyState
                } else {
                    dashboardGrid
                }
            }
            .navigationTitle("Dashboard")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button { showLibrary = true } label: {
                            Image(systemName: "plus")
                        }
                        .foregroundStyle(Theme.Colors.accent)

                        if !items.isEmpty {
                            Button(isEditing ? "Done" : "Edit") {
                                withAnimation(Theme.Anim.spring) {
                                    isEditing.toggle()
                                }
                            }
                            .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                }
            }
            .task {
                await loadDashboard()
            }
            .refreshable {
                await loadDashboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .widgetInjected)) { _ in
                Task { await loadDashboard() }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showLibrary) {
                WidgetLibraryView {
                    Task { await loadDashboard() }
                }
                .environmentObject(appState)
            }
        }
    }

    // MARK: - Dashboard Grid

    private var dashboardGrid: some View {
        GeometryReader { geo in
            let cellWidth = (geo.size.width - Theme.Spacing.md * 3) / 2
            let cellHeight = cellWidth // square cells

            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                    ForEach(items) { item in
                        DashboardCardView(
                            item: item,
                            serverURL: appState.serverURL,
                            apiKey: appState.apiKey,
                            cellHeight: cellHeight,
                            isEditing: isEditing,
                            onRemove: {
                                Task { await unpinItem(item) }
                            },
                            onCycleSize: {
                                Task { await cycleSize(item) }
                            }
                        )
                        .frame(height: item.size.cardHeight(cellHeight: cellHeight))
                        .gridCellColumns(item.size.colSpan)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.textTertiary)

            Text("No Widgets Yet")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Browse the widget library or ask your AI to create custom widgets.")
                .font(Theme.Typography.subhead)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Button {
                showLibrary = true
            } label: {
                Label("Browse Widgets", systemImage: "plus.square.on.square")
                    .font(Theme.Typography.subhead.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.xl)
        .glassCard()
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Actions

    private func loadDashboard() async {
        guard let client = appState.getAPIClient() else {
            isLoading = false
            return
        }
        do {
            items = try await client.getDashboard()
        } catch {
            errorMessage = "Failed to load dashboard: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func unpinItem(_ item: DashboardItemDTO) async {
        guard let client = appState.getAPIClient() else { return }
        let snapshot = items
        withAnimation(Theme.Anim.spring) {
            items.removeAll { $0.id == item.id }
        }
        do {
            try await client.unpinWidget(slug: item.slug)
        } catch {
            withAnimation(Theme.Anim.spring) { items = snapshot }
            errorMessage = "Failed to unpin: \(error.localizedDescription)"
        }
    }

    private func cycleSize(_ item: DashboardItemDTO) async {
        guard let client = appState.getAPIClient() else { return }
        let snapshot = items
        let newSize = item.size.next
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            withAnimation(Theme.Anim.spring) {
                items[idx] = DashboardItemDTO(
                    id: item.id, widgetId: item.widgetId, slug: item.slug,
                    title: item.title, size: newSize, position: item.position
                )
            }
        }
        do {
            _ = try await client.updateDashboardItem(slug: item.slug, size: newSize)
        } catch {
            withAnimation(Theme.Anim.spring) { items = snapshot }
            errorMessage = "Failed to resize: \(error.localizedDescription)"
        }
    }
}

// MARK: - WidgetSize Helpers

private extension WidgetSize {
    /// Card height based on a square cell height
    func cardHeight(cellHeight: CGFloat) -> CGFloat {
        switch self {
        case .small:
            return cellHeight
        case .medium:
            return cellHeight
        case .large:
            return cellHeight * 2 + Theme.Spacing.md
        }
    }

    var sizeIcon: String {
        switch self {
        case .small: return "square"
        case .medium: return "rectangle"
        case .large: return "square.fill"
        }
    }

    var sizeLabel: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }
}

// MARK: - Dashboard Card

private struct DashboardCardView: View {
    let item: DashboardItemDTO
    let serverURL: String
    let apiKey: String
    let cellHeight: CGFloat
    let isEditing: Bool
    let onRemove: () -> Void
    let onCycleSize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Theme.Spacing.sm) {
                Text(item.title)
                    .font(Theme.Typography.footnote.bold())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                if isEditing {
                    Button(action: onCycleSize) {
                        Text(item.size.sizeLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 22, height: 22)
                            .background(Theme.Colors.accent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.error)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                Theme.Colors.surface2.opacity(0.5),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: Theme.Radius.lg,
                    topTrailingRadius: Theme.Radius.lg
                )
            )

            // WebView
            if !serverURL.isEmpty {
                WidgetWebView(
                    slug: item.slug,
                    serverURL: serverURL,
                    apiKey: apiKey,
                    allowsScrolling: true,
                    isDashboard: true
                )
            }
        }
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.borderSubtle, lineWidth: 0.5)
        )
        .if(isEditing) { view in
            view.overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
