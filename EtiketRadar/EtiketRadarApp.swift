import SwiftUI
import UIKit
import Vision

// MARK: - EtiketRadar
// Tek dosya SwiftUI uygulaması.
// Tasarım: market/e-ticaret uygulaması yoğunluğu, iPhone 14 dikey ekran uyumu, 4 sekmeli alt menü.
// Backend: Tavily + Gemini Vercel servisleri. OpenAI API kullanılmaz.

@main
struct EtiketRadarApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - API Models

struct ProductOffer: Identifiable, Codable, Hashable {
    var id = UUID()
    var siteName: String
    var title: String
    var priceText: String
    var url: String
    var imageURL: String?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case siteName, title, priceText, url, imageURL, note
    }
}

struct SourceLink: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: String
    var sourceType: String?

    enum CodingKeys: String, CodingKey {
        case title, url, sourceType
    }
}

struct MedicineInfo: Codable, Hashable {
    var name: String?
    var activeIngredient: String?
    var form: String?
    var packageInfo: String?
    var imageURL: String?
}

struct MedicineResponse: Codable, Hashable {
    var query: String
    var medicine: MedicineInfo?
    var offers: [ProductOffer]
    var usageInstructions: [String]
    var sideEffects: [String]
    var warnings: [String]
    var sources: [SourceLink]
    var disclaimer: String?
}

struct LabelProductInfo: Codable, Hashable {
    var brand: String?
    var model: String?
    var productName: String?
    var description: String?
    var barcode: String?
    var detectedPrice: String?
    var imageURL: String?
    var specs: [String: String]?
}

struct LabelResponse: Codable, Hashable {
    var query: String
    var product: LabelProductInfo?
    var offers: [ProductOffer]
    var suggestions: [String]
    var comparisonSpecs: [String: String]?
    var sources: [SourceLink]
}

struct APIErrorResponse: Codable {
    var error: String
}

// MARK: - Local Models

enum MainTab: String, Codable, CaseIterable {
    case home
    case categories
    case compare
    case settings

    var title: String {
        switch self {
        case .home: return "Anasayfa"
        case .categories: return "Kategoriler"
        case .compare: return "Kıyasla"
        case .settings: return "Ayarlar"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .categories: return "square.grid.2x2"
        case .compare: return "point.3.connected.trianglepath.dotted"
        case .settings: return "gearshape"
        }
    }
}

enum SearchKind: String, Codable, Hashable {
    case medicine
    case label

    var title: String { self == .medicine ? "İlaç" : "Etiket" }
}

struct SearchHistoryItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: SearchKind
    var title: String
    var subtitle: String
    var date: Date
    var medicineResponse: MedicineResponse?
    var labelResponse: LabelResponse?
}

struct CompareItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var brand: String
    var model: String
    var description: String
    var imageURL: String?
    var bestPrice: String
    var bestStore: String
    var bestURL: String
    var specs: [String: String]
    var addedAt: Date

    init(response: LabelResponse) {
        let product = response.product
        let best = response.offers.first
        self.title = (product?.productName).clean ?? response.query
        self.brand = (product?.brand).clean ?? "-"
        self.model = (product?.model).clean ?? "-"
        self.description = (product?.description).clean ?? "-"
        self.imageURL = (product?.imageURL).clean ?? (best?.imageURL).clean
        self.bestPrice = (best?.priceText).clean ?? (product?.detectedPrice).clean ?? "Fiyat yok"
        self.bestStore = (best?.siteName).clean ?? "-"
        self.bestURL = (best?.url).clean ?? ""
        self.specs = response.comparisonSpecs ?? product?.specs ?? [:]
        self.addedAt = Date()
    }
}

// MARK: - Utilities

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var clean: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}

extension Optional where Wrapped == String {
    var clean: String? {
        switch self {
        case .some(let value): return value.clean
        case .none: return nil
        }
    }
}

extension Array where Element == ProductOffer {
    var sortedByVisiblePrice: [ProductOffer] {
        sorted { lhs, rhs in
            let lp = lhs.priceNumber ?? Double.greatestFiniteMagnitude
            let rp = rhs.priceNumber ?? Double.greatestFiniteMagnitude
            return lp < rp
        }
    }
}

extension ProductOffer {
    var priceNumber: Double? {
        let text = priceText
            .replacingOccurrences(of: "TL", with: "")
            .replacingOccurrences(of: "₺", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.".contains($0) }
        return Double(text)
    }
}

extension Date {
    var shortTR: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "dd MMM HH:mm"
        return f.string(from: self)
    }
}

extension NSError {
    static func userMessage(_ message: String) -> NSError {
        NSError(domain: "EtiketRadar", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func openExternalURL(_ raw: String) {
    guard let url = URL(string: raw), UIApplication.shared.canOpenURL(url) else { return }
    UIApplication.shared.open(url)
}

// MARK: - App Store / Persistence

final class AppDataStore: ObservableObject {
    @Published var history: [SearchHistoryItem] = [] { didSet { saveHistory() } }
    @Published var compareItems: [CompareItem] = [] { didSet { saveCompare() } }

    private let historyKey = "etiketradar.history.v3"
    private let compareKey = "etiketradar.compare.v3"

    init() {
        history = Self.load([SearchHistoryItem].self, key: historyKey) ?? []
        compareItems = Self.load([CompareItem].self, key: compareKey) ?? []
    }

    func addHistory(_ item: SearchHistoryItem) {
        history.removeAll { $0.title == item.title && $0.kind == item.kind }
        history.insert(item, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
    }

    func clearHistory() { history.removeAll() }

    func addCompare(_ response: LabelResponse) {
        let item = CompareItem(response: response)
        compareItems.removeAll { $0.title.lowercased() == item.title.lowercased() }
        compareItems.insert(item, at: 0)
        if compareItems.count > 20 { compareItems = Array(compareItems.prefix(20)) }
    }

    func removeCompare(_ item: CompareItem) { compareItems.removeAll { $0.id == item.id } }
    func clearCompare() { compareItems.removeAll() }

    private func saveHistory() { Self.save(history, key: historyKey) }
    private func saveCompare() { Self.save(compareItems, key: compareKey) }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - API Client

struct APIClient {
    var baseURL: String
    var apiKey: String

    private func endpoint(_ path: String) throws -> URL {
        var cleaned = baseURL.trimmed
        if cleaned.isEmpty { cleaned = "https://etiket-radar-backend.vercel.app/" }
        if !cleaned.hasSuffix("/") { cleaned += "/" }
        guard let url = URL(string: cleaned + path) else { throw NSError.userMessage("Backend URL hatalı.") }
        return url
    }

    func medicineSearch(query: String, ocrText: String? = nil) async throws -> MedicineResponse {
        try await post("v1/medicine-search", body: ["query": query, "ocrText": ocrText ?? ""])
    }

    func labelSearch(query: String, ocrText: String? = nil) async throws -> LabelResponse {
        try await post("v1/label-search", body: ["query": query, "ocrText": ocrText ?? ""])
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = try endpoint(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 95
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.trimmed.isEmpty { req.setValue("Bearer \(apiKey.trimmed)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NSError.userMessage("Sunucudan geçersiz cevap geldi.") }
        guard (200..<300).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw NSError.userMessage(err.error)
            }
            throw NSError.userMessage("Sunucu hatası: \(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NSError.userMessage("Sunucu cevabı çözümlenemedi: \(error.localizedDescription)")
        }
    }
}

// MARK: - OCR

final class OCRService {
    static func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw NSError.userMessage("Görsel okunamadı.") }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error { continuation.resume(throwing: error); return }
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    continuation.resume(returning: text)
                }
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["tr-TR", "en-US"]
                request.usesLanguageCorrection = true
                do { try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

// MARK: - Theme

enum Theme {
    static let blue = Color(red: 0.02, green: 0.38, blue: 0.95)
    static let deepBlue = Color(red: 0.04, green: 0.10, blue: 0.28)
    static let teal = Color(red: 0.00, green: 0.70, blue: 0.62)
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.08)
    static let green = Color(red: 0.00, green: 0.64, blue: 0.41)
    static let text = Color(red: 0.07, green: 0.10, blue: 0.20)
    static let subtext = Color(red: 0.36, green: 0.41, blue: 0.52)
    static let bg = Color(red: 0.975, green: 0.982, blue: 0.995)
    static let border = Color(red: 0.88, green: 0.91, blue: 0.95)
    static let softBlue = Color(red: 0.92, green: 0.96, blue: 1.00)
    static let softGreen = Color(red: 0.91, green: 0.985, blue: 0.96)

    static let screenGradient = LinearGradient(
        colors: [Color.white, Color(red: 0.97, green: 0.985, blue: 1.0)],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension View {
    func cardShadow(_ opacity: Double = 0.055, y: CGFloat = 8) -> some View {
        shadow(color: Color.black.opacity(opacity), radius: 16, x: 0, y: y)
    }

    func roundedCard(corner: CGFloat = 16) -> some View {
        background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .cardShadow()
    }
}

// MARK: - Root

struct RootView: View {
    @AppStorage("backendBaseURL") private var backendBaseURL = "https://etiket-radar-backend.vercel.app/"
    @AppStorage("appApiKey") private var appApiKey = "etiket-radar-123456"
    @StateObject private var store = AppDataStore()
    @State private var tab: MainTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            currentTab
                .environmentObject(store)
                .tint(Theme.blue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.screenGradient.ignoresSafeArea())

            MainTabBar(selected: $tab)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var currentTab: some View {
        switch tab {
        case .home:
            NavigationStack { HomeView(client: client, selectedTab: $tab) }
        case .categories:
            NavigationStack { CategoriesView(client: client) }
        case .compare:
            NavigationStack { CompareView() }
        case .settings:
            NavigationStack { SettingsView(backendBaseURL: $backendBaseURL, appApiKey: $appApiKey) }
        }
    }

    private var client: APIClient { APIClient(baseURL: backendBaseURL, apiKey: appApiKey) }
}

struct MainTabBar: View {
    @Binding var selected: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { item in
                Button { selected = item } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 21, weight: .semibold))
                            .frame(height: 23)
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(selected == item ? Theme.blue : Theme.subtext)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selected == item {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.blue.opacity(0.10))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 64)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.90), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 6)
    }
}

// MARK: - Shared Layout

struct AppScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            Theme.screenGradient.ignoresSafeArea()
            content()
        }
        .navigationBarHidden(true)
    }
}

struct HeaderBar: View {
    var title: String
    var showBack: Bool = false
    var showBell: Bool = true
    var showShare: Bool = false
    var shareAction: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 10) {
            if showBack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.text)
                        .frame(width: 42, height: 42)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                }
            }

            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            if showShare {
                Button { shareAction?() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .frame(width: 42, height: 42)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                }
            } else if showBell {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .frame(width: 42, height: 42)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: -4, y: 5)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String
    var scanAction: (() -> Void)? = nil
    var submitAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.subtext)
                .font(.system(size: 17, weight: .semibold))
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(size: 15, weight: .medium))
                .submitLabel(.search)
                .onSubmit { submitAction?() }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.subtext.opacity(0.75))
                        .font(.system(size: 18, weight: .bold))
                }
            }
            if let scanAction {
                Button(action: scanAction) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.text)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

struct LoadingOverlay: View {
    var message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.16).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(Theme.blue).scaleEffect(1.15)
                Text(message)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            .frame(width: 240)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .cardShadow(0.12, y: 12)
        }
    }
}

// MARK: - Home

struct HomeView: View {
    let client: APIClient
    @Binding var selectedTab: MainTab
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""
    @State private var showManualChoice = false
    @State private var goHomeLabel = false
    @State private var goHomeMedicine = false

    var body: some View {
        AppScreen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .center) {
                        Text("EtiketRadar")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(Theme.blue)
                        Spacer()
                        NotificationMiniButton()
                    }
                    .padding(.top, 8)

                    SearchBar(text: $searchText, placeholder: "Ürün, ilaç veya marka ara", scanAction: { showManualChoice = true }, submitAction: { showManualChoice = true })

                    HStack(spacing: 10) {
                        NavigationLink { LabelLandingView(client: client) } label: {
                            HomeActionCard(title: "Etiket", subtitle: "Ürün tara & karşılaştır", icon: "barcode.viewfinder", color: Theme.blue)
                        }
                        .buttonStyle(.plain)
                        NavigationLink { MedicineLandingView(client: client) } label: {
                            HomeActionCard(title: "İlaç", subtitle: "Fiyat & bilgi al", icon: "capsule.fill", color: Theme.teal)
                        }
                        .buttonStyle(.plain)
                    }

                    SectionHeader(title: "Kategoriler", actionTitle: "Tümünü Gör") { selectedTab = .categories }
                    CategoryRow()

                    Text("Hızlı İşlemler")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        QuickAction(title: "Fiyat Alarmı", subtitle: "İndirimleri kaçırma", icon: "bell.fill", color: Theme.blue)
                        QuickAction(title: "Favorilerim", subtitle: "Kaydettiğin ürünler", icon: "heart.fill", color: .red)
                        QuickAction(title: "Son Taramalar", subtitle: "Geçmiş taramalar", icon: "clock.arrow.circlepath", color: Theme.blue)
                        QuickAction(title: "Kıyaslamalarım", subtitle: "Karşılaştırmaların", icon: "point.3.connected.trianglepath.dotted", color: Theme.teal)
                    }

                    SectionHeader(title: "Son Taramalar", actionTitle: "Tümünü Gör") { selectedTab = .categories }
                    RecentScanScroller(items: store.history)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
        }
        .confirmationDialog("Arama türü seç", isPresented: $showManualChoice) {
            Button("Etiket / ürün olarak ara") { goHomeLabel = true }
            Button("İlaç olarak ara") { goHomeMedicine = true }
            Button("Vazgeç", role: .cancel) {}
        }
        .navigationDestination(isPresented: $goHomeLabel) {
            LabelLandingView(client: client, initialQuery: searchText)
        }
        .navigationDestination(isPresented: $goHomeMedicine) {
            MedicineLandingView(client: client, initialQuery: searchText)
        }
    }
}

struct NotificationMiniButton: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.text)
                .frame(width: 38, height: 38)
                .background(Color.white)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            Circle().fill(Color.red).frame(width: 7, height: 7).offset(x: -3, y: 4)
        }
    }
}

struct HomeActionCard: View {
    var title: String
    var subtitle: String
    var icon: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            LinearGradient(colors: [color, color.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardShadow(0.10, y: 8)
    }
}

struct SectionHeader: View {
    var title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
            Spacer()
            if let actionTitle {
                Button(action: { action?() }) {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.blue)
                }
            }
        }
    }
}

struct CategoryRow: View {
    let categories: [(String, String, Color)] = [
        ("Elektronik", "headphones", .gray),
        ("Kozmetik", "drop.fill", .pink),
        ("Ev & Yaşam", "house.fill", Theme.blue),
        ("Süpermarket", "cart.fill", Theme.teal),
        ("Bebek", "figure.and.child.holdinghands", .purple)
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(categories, id: \.0) { item in
                    VStack(spacing: 7) {
                        Image(systemName: item.1)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(item.2)
                            .frame(width: 46, height: 46)
                            .background(item.2.opacity(0.10))
                            .clipShape(Circle())
                        Text(item.0)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                    }
                    .frame(width: 70)
                }
            }
        }
    }
}

struct QuickAction: View {
    var title: String
    var subtitle: String
    var icon: String
    var color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.subtext)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(height: 56)
        .roundedCard(corner: 12)
    }
}

struct RecentScanScroller: View {
    var items: [SearchHistoryItem]

    var demoItems: [SearchHistoryItem] {
        [
            SearchHistoryItem(kind: .label, title: "Kablosuz Kulaklık", subtitle: "1.299,00 TL", date: Date(), medicineResponse: nil, labelResponse: nil),
            SearchHistoryItem(kind: .label, title: "Parfüm EDP 50 ml", subtitle: "849,00 TL", date: Date(), medicineResponse: nil, labelResponse: nil),
            SearchHistoryItem(kind: .medicine, title: "C Vitamini 1000 mg", subtitle: "199,00 TL", date: Date(), medicineResponse: nil, labelResponse: nil)
        ]
    }

    var body: some View {
        let source = items.isEmpty ? demoItems : Array(items.prefix(10))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(source) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(item.kind == .medicine ? Theme.softGreen : Theme.softBlue)
                            Image(systemName: item.kind == .medicine ? "capsule.fill" : "tag.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(item.kind == .medicine ? Theme.teal : Theme.blue)
                        }
                        .frame(height: 56)
                        Text(item.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.text)
                            .lineLimit(2)
                        Text(item.subtitle)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.blue)
                            .lineLimit(1)
                    }
                    .padding(10)
                    .frame(width: 118, height: 136)
                    .roundedCard(corner: 14)
                }
            }
        }
    }
}

// MARK: - Medicine Flow

struct MedicineLandingView: View {
    let client: APIClient
    var initialQuery: String = ""
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""
    @State private var showManual = false
    @State private var showCamera = false
    @State private var loadingMessage: String?
    @State private var errorMessage: String?
    @State private var result: MedicineResponse?
    @State private var navigate = false

    var body: some View {
        AppScreen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HeaderBar(title: "İlaç Asistanı", showBack: true, showBell: false)
                    SearchBar(text: $searchText, placeholder: "İlaç adı, etken madde veya firma ara", submitAction: { Task { await searchMedicine(query: searchText, ocrText: nil) } })
                        .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        OptionCard(title: "Manuel Ekle", subtitle: "İlaç adını yazarak ara", icon: "doc.badge.plus", color: Theme.blue) {
                            showManual = true
                        }
                        OptionCard(title: "Resim Çek", subtitle: "Kutu veya prospektüs", icon: "camera.fill", color: Theme.teal) {
                            showCamera = true
                        }
                    }
                    .padding(.horizontal, 16)

                    MedicineInfoCard()
                        .padding(.horizontal, 16)

                    MedicineFeatureStrip()
                        .padding(.horizontal, 16)

                    DisclaimerStrip(text: "Bilgiler yalnızca bilgilendirme amaçlıdır. Tıbbi tavsiye yerine geçmez.")
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 100)
                .padding(.top, 2)
            }
            if let loadingMessage { LoadingOverlay(message: loadingMessage) }
        }
        .onAppear { if !initialQuery.isEmpty && searchText.isEmpty { searchText = initialQuery } }
        .sheet(isPresented: $showManual) {
            ManualSearchSheet(title: "İlaç adı yaz", placeholder: "Örn: Majezik 100 mg veya Ofnol S %0.2") { query in
                showManual = false
                Task { await searchMedicine(query: query, ocrText: nil) }
            }
            .presentationDetents([.height(290)])
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker { image in
                showCamera = false
                Task { await handleImage(image) }
            }
        }
        .alert("Uyarı", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .navigationDestination(isPresented: $navigate) {
            if let result { MedicineResultView(response: result) }
        }
    }

    private func handleImage(_ image: UIImage) async {
        do {
            loadingMessage = "Fotoğraf okunuyor..."
            let text = try await OCRService.recognizeText(from: image)
            let query = bestMedicineQuery(from: text)
            await searchMedicine(query: query, ocrText: text)
        } catch {
            loadingMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func searchMedicine(query: String, ocrText: String?) async {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { errorMessage = "İlaç adı boş olamaz."; return }
        do {
            loadingMessage = "İlaç bilgileri aranıyor..."
            let response = try await client.medicineSearch(query: trimmed, ocrText: ocrText)
            result = response
            let title = (response.medicine?.name).clean ?? response.query
            let subtitle = (response.offers.first?.priceText).clean ?? (response.medicine?.activeIngredient).clean ?? "İlaç araması"
            store.addHistory(SearchHistoryItem(kind: .medicine, title: title, subtitle: subtitle, date: Date(), medicineResponse: response, labelResponse: nil))
            loadingMessage = nil
            navigate = true
        } catch {
            loadingMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func bestMedicineQuery(from text: String) -> String {
        let lines = text.split(separator: "\n").map { String($0).trimmed }.filter { $0.count >= 4 }
        let ignored = ["KULLAN", "SAKLA", "PROSPEKT", "BARKOD", "SERİ", "LOT", "SKT", "TABLET", "ML"]
        return lines.first { line in
            let u = line.uppercased()
            return !ignored.contains { u.contains($0) }
        } ?? text.replacingOccurrences(of: "\n", with: " ")
    }
}

struct OptionCard: View {
    var title: String
    var subtitle: String
    var icon: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 70, height: 70)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.subtext)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 158)
            .background(color.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(color.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct MedicineInfoCard: View {
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(Theme.blue)
                .frame(width: 58, height: 58)
                .background(Theme.blue.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Doğru bilgi, güvenli kullanım.")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("İlaçların güncel fiyatlarını, kullanım talimatlarını ve olası yan etkilerini öğrenin.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.subtext)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .roundedCard(corner: 16)
    }
}

struct MedicineFeatureStrip: View {
    let items = [("Güncel\nFiyatlar", "chart.line.uptrend.xyaxis", Theme.teal), ("Kullanım\nTalimatı", "doc.text.fill", Theme.blue), ("Yan Etki\nBilgileri", "shield.lefthalf.filled", Theme.green)]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                VStack(spacing: 8) {
                    Image(systemName: item.1)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(item.2)
                        .frame(width: 48, height: 48)
                        .background(item.2.opacity(0.11))
                        .clipShape(Circle())
                    Text(item.0)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .roundedCard(corner: 16)
    }
}

struct DisclaimerStrip: View {
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(Theme.subtext)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .roundedCard(corner: 14)
    }
}

// MARK: - Label Flow

struct LabelLandingView: View {
    let client: APIClient
    var initialQuery: String = ""
    @EnvironmentObject private var store: AppDataStore
    @State private var searchText = ""
    @State private var showManual = false
    @State private var showCamera = false
    @State private var loadingMessage: String?
    @State private var errorMessage: String?
    @State private var result: LabelResponse?
    @State private var navigate = false

    var body: some View {
        AppScreen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HeaderBar(title: "Etiket Karşılaştır", showBack: true, showBell: false)
                    SearchBar(text: $searchText, placeholder: "Marka, model, ürün veya barkod ara", submitAction: { Task { await searchLabel(query: searchText, ocrText: nil) } })
                        .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        OptionCard(title: "Ürün Ara", subtitle: "Marka veya model yaz", icon: "magnifyingglass", color: Theme.blue) { showManual = true }
                        OptionCard(title: "Etiket Çek", subtitle: "Raf etiketi veya kutu", icon: "viewfinder", color: Theme.teal) { showCamera = true }
                    }
                    .padding(.horizontal, 16)

                    LabelInfoCard()
                        .padding(.horizontal, 16)
                    CategoryRow()
                        .padding(.horizontal, 16)
                    DisclaimerStrip(text: "Fiyatlar anlık değişebilir. Satın almadan önce satıcı, stok ve kargo bilgisini kontrol edin.")
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 100)
                .padding(.top, 2)
            }
            if let loadingMessage { LoadingOverlay(message: loadingMessage) }
        }
        .onAppear { if !initialQuery.isEmpty && searchText.isEmpty { searchText = initialQuery } }
        .sheet(isPresented: $showManual) {
            ManualSearchSheet(title: "Ürün adı yaz", placeholder: "Örn: Sony WH-CH720N siyah") { query in
                showManual = false
                Task { await searchLabel(query: query, ocrText: nil) }
            }
            .presentationDetents([.height(290)])
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker { image in
                showCamera = false
                Task { await handleImage(image) }
            }
        }
        .alert("Uyarı", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .navigationDestination(isPresented: $navigate) {
            if let result { LabelResultView(response: result) }
        }
    }

    private func handleImage(_ image: UIImage) async {
        do {
            loadingMessage = "Etiket okunuyor..."
            let text = try await OCRService.recognizeText(from: image)
            let query = bestLabelQuery(from: text)
            await searchLabel(query: query, ocrText: text)
        } catch {
            loadingMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func searchLabel(query: String, ocrText: String?) async {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { errorMessage = "Ürün adı boş olamaz."; return }
        do {
            loadingMessage = "İnternet fiyatları aranıyor..."
            let response = try await client.labelSearch(query: trimmed, ocrText: ocrText)
            result = response
            let title = (response.product?.productName).clean ?? response.query
            let subtitle = (response.offers.first?.priceText).clean ?? (response.product?.description).clean ?? "Etiket araması"
            store.addHistory(SearchHistoryItem(kind: .label, title: title, subtitle: subtitle, date: Date(), medicineResponse: nil, labelResponse: response))
            loadingMessage = nil
            navigate = true
        } catch {
            loadingMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func bestLabelQuery(from text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").split(separator: " ").prefix(14).joined(separator: " ")
    }
}

struct LabelInfoCard: View {
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "tag.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(Theme.blue)
                .frame(width: 58, height: 58)
                .background(Theme.blue.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Mağazada fiyat kontrolü")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                Text("Elektronik, market, kozmetik ve mağaza ürünlerinde internet fiyatlarını karşılaştırın.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.subtext)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .roundedCard(corner: 16)
    }
}

// MARK: - Result Views

struct MedicineResultView: View {
    let response: MedicineResponse
    @State private var selectedOffer: ProductOffer?
    @State private var showShare = false
    @State private var shareURL: URL?

    private var medName: String { (response.medicine?.name).clean ?? response.query }
    private var active: String { (response.medicine?.activeIngredient).clean ?? "-" }
    private var packageInfo: String { (response.medicine?.packageInfo).clean ?? (response.medicine?.form).clean ?? "" }

    var body: some View {
        AppScreen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HeaderBar(title: "İlaç Sonuçları", showBack: true, showBell: false, showShare: true) { shareMedicinePDF() }
                    QueryChip(text: "Aramanız: \(response.query)")
                        .padding(.horizontal, 16)

                    MedicineHeroCompact(name: medName, active: active, packageInfo: packageInfo, imageURL: response.medicine?.imageURL)
                        .padding(.horizontal, 16)

                    OffersCard(title: "İnternet Fiyatları", offers: response.offers.sortedByVisiblePrice, buttonTitle: "Satın Al", highlightFirst: true) { offer in
                        selectedOffer = offer
                    }
                    .padding(.horizontal, 16)

                    ExpandableCard(title: "Kullanım Talimatı", icon: "doc.text", color: Theme.blue, items: response.usageInstructions)
                        .padding(.horizontal, 16)
                    ExpandableCard(title: "Yan Etkiler", icon: "cross.case.fill", color: .red, items: response.sideEffects)
                        .padding(.horizontal, 16)
                    if !response.warnings.isEmpty {
                        ExpandableCard(title: "Önemli Uyarılar", icon: "exclamationmark.shield.fill", color: Theme.orange, items: response.warnings)
                            .padding(.horizontal, 16)
                    }
                    DisclaimerStrip(text: response.disclaimer.clean ?? "Bu bilgiler bilgilendirme amaçlıdır. Doktorunuza veya eczacınıza danışmadan ilaç kullanmayınız.")
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 102)
            }
        }
        .fullScreenCover(item: $selectedOffer) { offer in
            PurchaseView(title: "Satın Al", productTitle: medName, subtitle: packageInfo.clean ?? active, offers: response.offers.sortedByVisiblePrice, initialOffer: offer, kind: .medicine)
        }
        .sheet(isPresented: $showShare) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
    }

    private func shareMedicinePDF() {
        let lines: [(String, [String])] = [
            ("İlaç", [medName, "Etken madde: \(active)", packageInfo]),
            ("Fiyatlar", response.offers.map { "\($0.siteName): \($0.priceText.clean ?? "Fiyat sayfada") - \($0.url)" }),
            ("Kullanım Talimatı", response.usageInstructions),
            ("Yan Etkiler", response.sideEffects),
            ("Uyarı", [response.disclaimer.clean ?? "Doktor tavsiyesi değildir."])
        ]
        shareURL = PDFMaker.make(title: "EtiketRadar İlaç Sonucu", sections: lines)
        showShare = shareURL != nil
    }
}

struct LabelResultView: View {
    let response: LabelResponse
    @EnvironmentObject private var store: AppDataStore
    @State private var selectedOffer: ProductOffer?
    @State private var showShare = false
    @State private var shareURL: URL?
    @State private var didAddCompare = false

    private var productTitle: String { (response.product?.productName).clean ?? response.query }
    private var productSubtitle: String {
        [(response.product?.brand).clean, (response.product?.model).clean].compactMap { $0 }.joined(separator: " ").clean ?? "Ürün karşılaştırması"
    }

    var body: some View {
        AppScreen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HeaderBar(title: "Etiket Karşılaştır", showBack: true, showBell: false, showShare: true) { shareLabelPDF() }
                    ProductHeroCompact(product: response.product, fallbackTitle: productTitle)
                        .padding(.horizontal, 16)
                    FollowCard()
                        .padding(.horizontal, 16)
                    OffersCard(title: "Fiyat Karşılaştırması", offers: response.offers.sortedByVisiblePrice, buttonTitle: nil, highlightFirst: true) { offer in
                        selectedOffer = offer
                    }
                    .padding(.horizontal, 16)
                    if let best = response.offers.sortedByVisiblePrice.first {
                        Button { selectedOffer = best } label: {
                            HStack {
                                Text("Siteye Git")
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(.horizontal, 16)
                    }
                    Button {
                        store.addCompare(response)
                        didAddCompare = true
                    } label: {
                        HStack {
                            Image(systemName: didAddCompare ? "checkmark.circle.fill" : "plus.circle.fill")
                            Text(didAddCompare ? "Kıyaslamaya eklendi" : "Karşılaştırmaya ekle")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(didAddCompare ? Theme.green : Theme.blue)
                        .padding(14)
                        .roundedCard(corner: 14)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)

                    if !response.suggestions.isEmpty {
                        ExpandableCard(title: "Alışveriş Tavsiyeleri", icon: "lightbulb.fill", color: Theme.orange, items: response.suggestions)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 102)
            }
        }
        .fullScreenCover(item: $selectedOffer) { offer in
            PurchaseView(title: "Siteye Git", productTitle: productTitle, subtitle: productSubtitle, offers: response.offers.sortedByVisiblePrice, initialOffer: offer, kind: .label)
        }
        .sheet(isPresented: $showShare) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
    }

    private func shareLabelPDF() {
        let product = response.product
        let lines: [(String, [String])] = [
            ("Ürün", [productTitle, "Marka: \((product?.brand).clean ?? "-")", "Model: \((product?.model).clean ?? "-")", (product?.description).clean ?? ""]),
            ("Fiyatlar", response.offers.map { "\($0.siteName): \($0.priceText.clean ?? "Fiyat sayfada") - \($0.url)" }),
            ("Özellikler", (response.comparisonSpecs ?? product?.specs ?? [:]).map { "\($0.key): \($0.value)" }),
            ("Tavsiyeler", response.suggestions)
        ]
        shareURL = PDFMaker.make(title: "EtiketRadar Ürün Sonucu", sections: lines)
        showShare = shareURL != nil
    }
}

struct QueryChip: View {
    var text: String
    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
            Spacer()
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.blue)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.softBlue)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct MedicineHeroCompact: View {
    var name: String
    var active: String
    var packageInfo: String
    var imageURL: String?
    @State private var showImage = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncThumb(url: imageURL, symbol: "capsule.fill", tint: Theme.blue)
                .frame(width: 126, height: 88)
                .onTapGesture { showImage = true }
            VStack(alignment: .leading, spacing: 7) {
                Text(name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text("Etken Madde: \(active)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.subtext)
                    .lineLimit(1)
                if !packageInfo.isEmpty {
                    Text(packageInfo)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.subtext)
                        .lineLimit(1)
                }
                Label("Yapay Zeka ile Doğrulandı", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.teal)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.teal.opacity(0.10))
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .roundedCard(corner: 15)
        .sheet(isPresented: $showImage) { LargeImageView(url: imageURL, title: name) }
    }
}

struct ProductHeroCompact: View {
    var product: LabelProductInfo?
    var fallbackTitle: String
    @State private var showImage = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncThumb(url: product?.imageURL, symbol: "headphones", tint: Theme.blue)
                .frame(width: 126, height: 104)
                .onTapGesture { showImage = true }
            VStack(alignment: .leading, spacing: 7) {
                Text((product?.brand).clean ?? fallbackTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text((product?.model).clean ?? (product?.productName).clean ?? fallbackTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                Text((product?.description).clean ?? "Ürün bilgisi AI ile algılandı")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.subtext)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .roundedCard(corner: 15)
        .sheet(isPresented: $showImage) { LargeImageView(url: product?.imageURL, title: fallbackTitle) }
    }
}

struct FollowCard: View {
    var body: some View {
        HStack {
            Label("237 kişi bu ürünü takip ediyor", systemImage: "person.2.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.subtext)
            Spacer()
            Image(systemName: "heart")
                .foregroundColor(Theme.subtext)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .roundedCard(corner: 12)
    }
}

struct AsyncThumb: View {
    var url: String?
    var symbol: String
    var tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.98, green: 0.985, blue: 1.0))
            if let urlString = url.clean, let realURL = URL(string: urlString) {
                AsyncImage(url: realURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(tint)
                    case .success(let image):
                        image.resizable().scaledToFit().padding(6)
                    case .failure:
                        Image(systemName: symbol).font(.system(size: 34, weight: .bold)).foregroundColor(tint)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(tint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

struct OffersCard: View {
    var title: String
    var offers: [ProductOffer]
    var buttonTitle: String?
    var highlightFirst: Bool = false
    var onTap: (ProductOffer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
            if offers.isEmpty {
                Text("Sonuç bulunamadı. Farklı bir isim veya modelle tekrar deneyin.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.subtext)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(offers.prefix(8).enumerated()), id: \.offset) { index, offer in
                        OfferRow(offer: offer, rank: index + 1, isBest: highlightFirst && index == 0, buttonTitle: buttonTitle) {
                            onTap(offer)
                        }
                        if index < min(offers.count, 8) - 1 { Divider().padding(.leading, 34) }
                    }
                }
                Text("Fiyatlar kaynak sitelerden alınır; stok ve kargo bilgisi değişebilir.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.subtext)
                    .padding(.top, 3)
            }
        }
        .padding(12)
        .roundedCard(corner: 16)
    }
}

struct OfferRow: View {
    var offer: ProductOffer
    var rank: Int
    var isBest: Bool
    var buttonTitle: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SiteBadge(name: offer.siteName, rank: rank, isBest: isBest)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(offer.siteName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(siteColor(offer.siteName))
                            .lineLimit(1)
                        if isBest {
                            Text("En Uygun")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Theme.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Theme.green.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                    Text(offer.note.clean ?? offer.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.subtext)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(offer.priceText.clean ?? "Fiyat sayfada")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                if let buttonTitle {
                    Text(buttonTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.subtext.opacity(0.7))
                }
            }
            .padding(.vertical, 9)
            .background(isBest ? Theme.green.opacity(0.055) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func siteColor(_ name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("hepsi") { return Theme.orange }
        if lower.contains("trendyol") { return .black }
        if lower.contains("amazon") { return .black }
        if lower.contains("migros") { return .orange }
        if lower.contains("teknosa") { return .blue }
        return Theme.text
    }
}

struct SiteBadge: View {
    var name: String
    var rank: Int
    var isBest: Bool

    var body: some View {
        ZStack {
            Circle().fill(isBest ? Theme.green : Theme.softBlue)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(isBest ? .white : Theme.blue)
        }
        .frame(width: 30, height: 30)
    }
}

struct ExpandableCard: View {
    var title: String
    var icon: String
    var color: Color
    var items: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.20)) { expanded.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(color)
                        .frame(width: 32, height: 32)
                        .background(color.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.text)
                }
            }
            .buttonStyle(.plain)
            if expanded || items.count <= 3 {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(color).frame(width: 5, height: 5).padding(.top, 6)
                            Text(item)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(12)
        .roundedCard(corner: 14)
    }
}

// MARK: - Purchase

enum PurchaseKind { case medicine, label }

struct PurchaseView: View {
    var title: String
    var productTitle: String
    var subtitle: String
    var offers: [ProductOffer]
    var initialOffer: ProductOffer
    var kind: PurchaseKind
    @Environment(\.dismiss) private var dismiss
    @State private var selected: ProductOffer

    init(title: String, productTitle: String, subtitle: String, offers: [ProductOffer], initialOffer: ProductOffer, kind: PurchaseKind) {
        self.title = title
        self.productTitle = productTitle
        self.subtitle = subtitle
        self.offers = offers.isEmpty ? [initialOffer] : offers
        self.initialOffer = initialOffer
        self.kind = kind
        self._selected = State(initialValue: initialOffer)
    }

    var body: some View {
        ZStack {
            Theme.screenGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.text)
                            .frame(width: 42, height: 42)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            AsyncThumb(url: selected.imageURL, symbol: kind == .medicine ? "capsule.fill" : "tag.fill", tint: Theme.blue)
                                .frame(width: 96, height: 82)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(productTitle)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.text)
                                    .lineLimit(2)
                                Text(subtitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.subtext)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .roundedCard(corner: 16)

                        VStack(spacing: 0) {
                            ForEach(offers) { offer in
                                Button { selected = offer } label: {
                                    HStack(spacing: 10) {
                                        SiteBadge(name: offer.siteName, rank: 1, isBest: offer.id == selected.id)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(offer.siteName)
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundColor(Theme.text)
                                            Text(offer.note.clean ?? offer.title)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(Theme.subtext)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Text(offer.priceText.clean ?? "Fiyat sayfada")
                                            .font(.system(size: 15, weight: .black, design: .rounded))
                                            .foregroundColor(Theme.blue)
                                        Image(systemName: "arrow.up.right.square")
                                            .foregroundColor(Theme.blue)
                                    }
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                if offer.id != offers.last?.id { Divider().padding(.leading, 42) }
                            }
                        }
                        .padding(12)
                        .roundedCard(corner: 16)

                        DisclaimerStrip(text: kind == .medicine ? "Fiyatlar bilgilendirme amaçlıdır. Satın almadan önce kaynak siteyi ve eczane bilgisini kontrol edin." : "Satın almadan önce stok, satıcı ve kargo bilgisini kontrol edin.")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 112)
                }
            }

            VStack(spacing: 9) {
                Spacer()
                Button { openExternalURL(selected.url) } label: {
                    HStack {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("Siteye Git")
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button { dismiss() } label: {
                    Text("Kapat")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }
}

// MARK: - Categories / History

struct CategoriesView: View {
    let client: APIClient
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        AppScreen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HeaderBar(title: "Kategoriler", showBack: false, showBell: true)
                    Text("Arama Geçmişi")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 16)
                    if store.history.isEmpty {
                        EmptyState(icon: "clock", title: "Henüz geçmiş yok", subtitle: "Etiket veya ilaç araması yaptığında burada görünecek.")
                            .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 9) {
                            ForEach(store.history) { item in
                                HistoryRow(item: item)
                            }
                        }
                        .padding(.horizontal, 16)
                        Button(role: .destructive) { store.clearHistory() } label: {
                            Text("Aramaları Temizle")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }
}

struct HistoryRow: View {
    var item: SearchHistoryItem

    var body: some View {
        NavigationLink {
            if let med = item.medicineResponse {
                MedicineResultView(response: med)
            } else if let label = item.labelResponse {
                LabelResultView(response: label)
            } else {
                Text("Bu demo kayıt yeniden açılamıyor.")
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.kind == .medicine ? "capsule.fill" : "tag.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(item.kind == .medicine ? Theme.teal : Theme.blue)
                    .frame(width: 42, height: 42)
                    .background((item.kind == .medicine ? Theme.teal : Theme.blue).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text("\(item.subtitle) • \(item.date.shortTR)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.subtext)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.subtext)
            }
            .padding(12)
            .roundedCard(corner: 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compare

struct CompareView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        AppScreen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HeaderBar(title: "Kıyasla", showBack: false, showBell: false)
                    if store.compareItems.isEmpty {
                        EmptyState(icon: "point.3.connected.trianglepath.dotted", title: "Kıyas sepeti boş", subtitle: "Etiket sonuçlarından ürünleri karşılaştırmaya ekleyebilirsin.")
                            .padding(.horizontal, 16)
                    } else {
                        HStack {
                            Text("Seçilen Ürünler")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.text)
                            Spacer()
                            Button("Temizle") { store.clearCompare() }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 16)
                        ForEach(store.compareItems) { item in
                            CompareItemCard(item: item) { store.removeCompare(item) }
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }
}

struct CompareItemCard: View {
    var item: CompareItem
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AsyncThumb(url: item.imageURL, symbol: "tag.fill", tint: Theme.blue)
                    .frame(width: 70, height: 62)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)
                    Text("\(item.brand) • \(item.model)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.subtext)
                        .lineLimit(1)
                    Text("\(item.bestStore) - \(item.bestPrice)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.blue)
                }
                Spacer()
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
            }
            if !item.specs.isEmpty {
                VStack(spacing: 5) {
                    ForEach(item.specs.sorted(by: { $0.key < $1.key }).prefix(5), id: \.key) { key, value in
                        HStack {
                            Text(key)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.subtext)
                            Spacer()
                            Text(value)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .background(Color(red: 0.98, green: 0.99, blue: 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(12)
        .roundedCard(corner: 14)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Binding var backendBaseURL: String
    @Binding var appApiKey: String

    var body: some View {
        AppScreen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HeaderBar(title: "Ayarlar", showBack: false, showBell: false)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Backend")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Theme.text)
                        TextField("Backend URL", text: $backendBaseURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .font(.system(size: 14, weight: .medium))
                            .padding(12)
                            .background(Color(red: 0.97, green: 0.985, blue: 1.0))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        SecureField("Uygulama API anahtarı", text: $appApiKey)
                            .font(.system(size: 14, weight: .medium))
                            .padding(12)
                            .background(Color(red: 0.97, green: 0.985, blue: 1.0))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(14)
                    .roundedCard(corner: 16)
                    .padding(.horizontal, 16)

                    SettingsInfo(title: "Ucuz altyapı", text: "Tavily ve Gemini anahtarları iPhone içine yazılmaz. Anahtarlar sadece Vercel Environment Variables içinde tutulur.")
                        .padding(.horizontal, 16)
                    SettingsInfo(title: "İlaç uyarısı", text: "Bu uygulamadaki ilaç bilgileri doktor veya eczacı tavsiyesi değildir. Prospektüs ve resmi kaynaklar kontrol edilmelidir.")
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 100)
            }
        }
    }
}

struct SettingsInfo: View {
    var title: String
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.text)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .roundedCard(corner: 16)
    }
}

struct EmptyState: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(Theme.blue)
                .frame(width: 86, height: 86)
                .background(Theme.blue.opacity(0.10))
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.subtext)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .roundedCard(corner: 16)
    }
}

// MARK: - Manual Search Sheet

struct ManualSearchSheet: View {
    var title: String
    var placeholder: String
    var onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(Theme.border)
                .frame(width: 46, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .font(.system(size: 16, weight: .medium))
                .padding(14)
                .background(Color(red: 0.97, green: 0.985, blue: 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border, lineWidth: 1))
                .onSubmit { submit() }
            Button { submit() } label: {
                Text("Ara")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            Button("Vazgeç") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.subtext)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .background(Theme.screenGradient.ignoresSafeArea())
    }

    private func submit() {
        let q = text.trimmed
        guard !q.isEmpty else { return }
        onSubmit(q)
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Image Preview

struct LargeImageView: View {
    var url: String?
    var title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let urlString = url.clean, let realURL = URL(string: urlString) {
                    AsyncImage(url: realURL) { phase in
                        switch phase {
                        case .empty: ProgressView().tint(.white)
                        case .success(let image): image.resizable().scaledToFit().padding()
                        case .failure: Image(systemName: "photo").font(.largeTitle).foregroundColor(.white)
                        @unknown default: EmptyView()
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Kapat") { dismiss() }.foregroundColor(.white) } }
        }
    }
}

// MARK: - Share / PDF

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum PDFMaker {
    static func make(title: String, sections: [(String, [String])]) -> URL? {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EtiketRadar_\(UUID().uuidString.prefix(8)).pdf")

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = 42
                let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.black]
                let hAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.black]
                let bAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.darkGray]
                title.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
                y += 38
                for section in sections {
                    if y > pageHeight - 100 { ctx.beginPage(); y = 42 }
                    section.0.draw(at: CGPoint(x: margin, y: y), withAttributes: hAttrs)
                    y += 22
                    for line in section.1 where !line.trimmed.isEmpty {
                        if y > pageHeight - 60 { ctx.beginPage(); y = 42 }
                        let rect = CGRect(x: margin, y: y, width: pageWidth - 2 * margin, height: 36)
                        ("• " + line).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: bAttrs, context: nil)
                        y += 33
                    }
                    y += 10
                }
            }
            return url
        } catch { return nil }
    }
}
