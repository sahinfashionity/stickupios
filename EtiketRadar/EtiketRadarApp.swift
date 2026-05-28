import SwiftUI
import UIKit
import Vision

@main
struct EtiketRadarApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - Data Models

struct ProductOffer: Identifiable, Codable, Hashable {
    var id = UUID()
    let siteName: String
    let title: String
    let priceText: String
    let url: String
    let imageURL: String?
    let note: String?

    enum CodingKeys: String, CodingKey { case siteName, title, priceText, url, imageURL, note }
}

struct SourceLink: Identifiable, Codable, Hashable {
    var id = UUID()
    let title: String
    let url: String
    let sourceType: String?

    enum CodingKeys: String, CodingKey { case title, url, sourceType }
}

struct MedicineInfo: Codable, Hashable {
    let name: String?
    let activeIngredient: String?
    let form: String?
    let packageInfo: String?
    let imageURL: String?
}

struct MedicineResponse: Codable, Hashable {
    let query: String
    let medicine: MedicineInfo?
    let offers: [ProductOffer]
    let usageInstructions: [String]
    let sideEffects: [String]
    let warnings: [String]
    let sources: [SourceLink]
    let disclaimer: String?
}

struct LabelProductInfo: Codable, Hashable {
    let brand: String?
    let model: String?
    let productName: String?
    let description: String?
    let barcode: String?
    let detectedPrice: String?
    let imageURL: String?
    let specs: [String: String]?
}

struct LabelResponse: Codable, Hashable {
    let query: String
    let product: LabelProductInfo?
    let offers: [ProductOffer]
    let suggestions: [String]
    let comparisonSpecs: [String: String]?
    let sources: [SourceLink]
}

struct APIErrorResponse: Codable { let error: String }

enum AppTab: CaseIterable {
    case home, history, compare, settings

    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .history: return "Geçmiş"
        case .compare: return "Kıyasla"
        case .settings: return "Ayarlar"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.fill"
        case .compare: return "square.split.2x2.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct SearchHistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let kind: String
    let title: String
    let subtitle: String
    let medicine: MedicineResponse?
    let label: LabelResponse?

    init(kind: String, title: String, subtitle: String, medicine: MedicineResponse? = nil, label: LabelResponse? = nil) {
        self.id = UUID()
        self.date = Date()
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.medicine = medicine
        self.label = label
    }
}

struct CompareItem: Identifiable, Codable, Hashable {
    let id: UUID
    let addedAt: Date
    let title: String
    let subtitle: String
    let imageURL: String?
    let bestPrice: String
    let bestStore: String
    let specs: [String: String]
    let offers: [ProductOffer]
    let sources: [SourceLink]

    init(response: LabelResponse) {
        let product = response.product
        let best = response.offers.first
        self.id = UUID()
        self.addedAt = Date()
        self.title = product?.productName.clean ?? response.query
        self.subtitle = [product?.brand.clean, product?.model.clean, product?.description.clean].compactMap { $0 }.joined(separator: " • ")
        self.imageURL = product?.imageURL.clean ?? best?.imageURL.clean
        self.bestPrice = best?.priceText.clean ?? product?.detectedPrice.clean ?? "Fiyat yok"
        self.bestStore = best?.siteName ?? "Kaynak yok"
        self.specs = product?.specs ?? response.comparisonSpecs ?? [:]
        self.offers = response.offers
        self.sources = response.sources
    }
}

@MainActor
final class SearchHistoryStore: ObservableObject {
    @Published private(set) var items: [SearchHistoryItem] = []
    private let key = "etiketRadarSearchHistoryV2"

    init() { load() }

    func add(_ item: SearchHistoryItem) {
        items.removeAll { $0.title == item.title && $0.kind == item.kind }
        items.insert(item, at: 0)
        items = Array(items.prefix(40))
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SearchHistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
final class CompareBasketStore: ObservableObject {
    @Published private(set) var items: [CompareItem] = []
    private let key = "etiketRadarCompareBasketV2"

    init() { load() }

    func contains(response: LabelResponse) -> Bool {
        let title = response.product?.productName.clean ?? response.query
        return items.contains { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    func toggle(response: LabelResponse) {
        let item = CompareItem(response: response)
        if let index = items.firstIndex(where: { $0.title.caseInsensitiveCompare(item.title) == .orderedSame }) {
            items.remove(at: index)
        } else {
            items.insert(item, at: 0)
        }
        items = Array(items.prefix(12))
        save()
    }

    func remove(_ item: CompareItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CompareItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - API Client

struct APIClient {
    let baseURL: String
    let apiKey: String

    private func endpoint(_ path: String) throws -> URL {
        var clean = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { clean = "https://etiket-radar-backend.vercel.app/" }
        if !clean.hasSuffix("/") { clean += "/" }
        guard let url = URL(string: clean + path) else { throw NSError.userMessage("Backend URL hatalı.") }
        return url
    }

    func medicineSearch(query: String, ocrText: String? = nil) async throws -> MedicineResponse {
        try await post("v1/medicine-search", body: ["query": query, "ocrText": ocrText ?? ""])
    }

    func labelSearch(query: String, ocrText: String? = nil) async throws -> LabelResponse {
        try await post("v1/label-search", body: ["query": query, "ocrText": ocrText ?? ""])
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty { request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NSError.userMessage("Sunucudan geçersiz cevap geldi.") }
        guard (200..<300).contains(http.statusCode) else {
            if let decoded = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw NSError.userMessage(decoded.error)
            }
            throw NSError.userMessage("Sunucu hatası: \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension NSError {
    static func userMessage(_ message: String) -> NSError {
        NSError(domain: "EtiketRadar", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
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
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Theme

struct ERTheme {
    static let navy = Color(red: 0.03, green: 0.06, blue: 0.18)
    static let ink = Color(red: 0.08, green: 0.12, blue: 0.25)
    static let muted = Color(red: 0.38, green: 0.45, blue: 0.58)
    static let blue = Color(red: 0.02, green: 0.38, blue: 0.96)
    static let cyan = Color(red: 0.08, green: 0.77, blue: 0.88)
    static let emerald = Color(red: 0.00, green: 0.62, blue: 0.48)
    static let lightStroke = Color(red: 0.80, green: 0.88, blue: 1.0)

    static let background = LinearGradient(
        colors: [Color(red: 0.96, green: 0.985, blue: 1.0), .white, Color(red: 0.93, green: 0.97, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let blueGradient = LinearGradient(
        colors: [Color(red: 0.02, green: 0.12, blue: 0.34), Color(red: 0.03, green: 0.34, blue: 0.88)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let greenGradient = LinearGradient(
        colors: [Color(red: 0.00, green: 0.38, blue: 0.34), Color(red: 0.08, green: 0.74, blue: 0.60)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func softShadow(_ color: Color = .black, opacity: Double = 0.08, radius: CGFloat = 18, y: CGFloat = 9) -> some View {
        shadow(color: color.opacity(opacity), radius: radius, x: 0, y: y)
    }
}

extension Optional where Wrapped == String {
    var clean: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

extension String {
    /// Boşlukları temizler; boş string ise nil döndürür.
    /// Not: Bazı yerlerde non-optional String üzerinde `.clean` kullanıldığı için
    /// bu property build hatasını önlemek amacıyla özellikle eklendi.
    var clean: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var cleanOrNil: String? {
        clean
    }
}

// MARK: - Root

struct RootView: View {
    @AppStorage("backendBaseURL") private var backendBaseURL = "https://etiket-radar-backend.vercel.app/"
    @AppStorage("appApiKey") private var appApiKey = "etiket-radar-123456"
    @State private var selectedTab: AppTab = .home
    @StateObject private var historyStore = SearchHistoryStore()
    @StateObject private var compareBasket = CompareBasketStore()

    private var client: APIClient { APIClient(baseURL: backendBaseURL, apiKey: appApiKey) }

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            currentScreen
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(historyStore)
        .environmentObject(compareBasket)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 5)
                .background(Color.clear)
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch selectedTab {
        case .home:
            NavigationStack { HomeView(client: client) }
        case .history:
            NavigationStack { HistoryView() }
        case .compare:
            NavigationStack { CompareView() }
        case .settings:
            NavigationStack { SettingsView(backendBaseURL: $backendBaseURL, appApiKey: $appApiKey) }
        }
    }
}

// MARK: - Home

struct HomeView: View {
    let client: APIClient

    var body: some View {
        AppScaffold {
            VStack(spacing: 16) {
                BrandHeader(compact: false)
                    .padding(.top, 4)

                NavigationLink { LabelLandingView(client: client) } label: {
                    HomeActionCard(
                        title: "Etiket",
                        subtitle: "Ürün fiyatlarını karşılaştır",
                        systemIcon: "tag.fill",
                        gradient: ERTheme.blueGradient,
                        accent: ERTheme.blue,
                        visual: .tag
                    )
                }
                .buttonStyle(.plain)

                NavigationLink { MedicineLandingView(client: client) } label: {
                    HomeActionCard(
                        title: "İlaç",
                        subtitle: "Fiyat, kullanım ve yan etkiler",
                        systemIcon: "capsule.fill",
                        gradient: ERTheme.greenGradient,
                        accent: ERTheme.emerald,
                        visual: .medicine
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 98)
        }
    }
}

// MARK: - Medicine Flow

struct MedicineLandingView: View {
    let client: APIClient
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: SearchHistoryStore
    @State private var showManual = false
    @State private var showCamera = false
    @State private var loadingMessage: String?
    @State private var errorMessage: String?
    @State private var result: MedicineResponse?
    @State private var navigate = false

    var body: some View {
        AppScaffold {
            VStack(spacing: 14) {
                PageHeader(title: "İlaç Asistanı", subtitle: "İlaç bilgilerini hızlıca öğren", showBack: true, onBack: { dismiss() })

                FeatureCard(
                    title: "Manuel Ekle",
                    subtitle: "İlacın adını yazarak ara",
                    icon: "keyboard.fill",
                    gradient: ERTheme.blueGradient,
                    accent: ERTheme.blue,
                    visual: .keyboard,
                    action: { showManual = true }
                )

                FeatureCard(
                    title: "Fotoğraf Çek",
                    subtitle: "Kutunun fotoğrafını çek, AI algılasın",
                    icon: "camera.fill",
                    gradient: ERTheme.greenGradient,
                    accent: ERTheme.emerald,
                    visual: .medicineScan,
                    action: { showCamera = true }
                )

                InfoPanel(
                    icon: "shield.checkered",
                    title: "Güvenliğiniz önceliğimiz",
                    text: "Fiyat, kullanım talimatı ve yan etkiler gibi bilgileri resmi kaynaklarla birlikte gösterir."
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
        .overlay { if let loadingMessage { LoadingOverlay(message: loadingMessage) } }
        .sheet(isPresented: $showManual) {
            ManualSearchSheet(title: "İlaç adı yaz", placeholder: "Örn: Majezik 100 mg veya Ofnol S") { query in
                showManual = false
                Task { await searchMedicine(query: query, ocrText: nil) }
            }
            .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker { image in
                showCamera = false
                Task { await readMedicineImage(image) }
            }
        }
        .alert("Uyarı", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .navigationDestination(isPresented: $navigate) {
            if let result { MedicineResultView(response: result) }
        }
    }

    private func readMedicineImage(_ image: UIImage) async {
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
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { errorMessage = "İlaç adı boş olamaz."; return }
        do {
            loadingMessage = "İlaç bilgileri aranıyor..."
            result = try await client.medicineSearch(query: clean, ocrText: ocrText)
            if let result {
                historyStore.add(SearchHistoryItem(
                    kind: "medicine",
                    title: result.medicine?.name.clean ?? result.query,
                    subtitle: result.medicine?.activeIngredient.clean ?? "İlaç araması",
                    medicine: result
                ))
            }
            loadingMessage = nil
            navigate = true
        } catch {
            loadingMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func bestMedicineQuery(from text: String) -> String {
        let ignored = ["KULLAN", "PROSPEKT", "BARKOD", "SERİ", "LOT", "SKT", "ML", "TABLET", "SAKL"]
        let lines = text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }
        if let candidate = lines.first(where: { line in
            let upper = line.uppercased()
            return !ignored.contains(where: { upper.contains($0) })
        }) { return candidate }
        return text.replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Label Flow

struct LabelLandingView: View {
    let client: APIClient
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: SearchHistoryStore
    @State private var showManual = false
    @State private var showCamera = false
    @State private var loadingMessage: String?
    @State private var errorMessage: String?
    @State private var result: LabelResponse?
    @State private var navigate = false

    var body: some View {
        AppScaffold {
            VStack(spacing: 14) {
                PageHeader(title: "Etiket Karşılaştır", subtitle: "Mağaza fiyatını internette kontrol et", showBack: true, onBack: { dismiss() })

                FeatureCard(
                    title: "Etiket Fotoğrafı",
                    subtitle: "Raf etiketi veya ürün kutusunu çek",
                    icon: "viewfinder",
                    gradient: ERTheme.blueGradient,
                    accent: ERTheme.blue,
                    visual: .tagScan,
                    action: { showCamera = true }
                )

                FeatureCard(
                    title: "Manuel Ürün Ara",
                    subtitle: "Marka, model veya barkod yaz",
                    icon: "magnifyingglass",
                    gradient: ERTheme.greenGradient,
                    accent: ERTheme.emerald,
                    visual: .keyboard,
                    action: { showManual = true }
                )

                InfoPanel(
                    icon: "cart.badge.questionmark",
                    title: "Mağazada hızlı kontrol",
                    text: "Elektronik, market ve mağaza ürünlerinde internet fiyatlarını karşılaştır."
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
        .overlay { if let loadingMessage { LoadingOverlay(message: loadingMessage) } }
        .sheet(isPresented: $showManual) {
            ManualSearchSheet(title: "Ürün adı yaz", placeholder: "Örn: Sony WH-CH720N siyah") { query in
                showManual = false
                Task { await searchLabel(query: query, ocrText: nil) }
            }
            .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker { image in
                showCamera = false
                Task { await readLabelImage(image) }
            }
        }
        .alert("Uyarı", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .navigationDestination(isPresented: $navigate) {
            if let result { LabelResultView(response: result) }
        }
    }

    private func readLabelImage(_ image: UIImage) async {
        do {
            loadingMessage = "Etiket okunuyor..."
            let text = try await OCRService.recognizeText(from: image)
            let query = text.replacingOccurrences(of: "\n", with: " ").split(separator: " ").prefix(14).joined(separator: " ")
            await searchLabel(query: query, ocrText: text)
        } catch {
            loadingMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func searchLabel(query: String, ocrText: String?) async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { errorMessage = "Ürün adı boş olamaz."; return }
        do {
            loadingMessage = "İnternet fiyatları aranıyor..."
            result = try await client.labelSearch(query: clean, ocrText: ocrText)
            if let result {
                historyStore.add(SearchHistoryItem(
                    kind: "label",
                    title: result.product?.productName.clean ?? result.query,
                    subtitle: result.offers.first?.priceText.clean ?? result.product?.description.clean ?? "Etiket araması",
                    label: result
                ))
            }
            loadingMessage = nil
            navigate = true
        } catch {
            loadingMessage = nil
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Result Screens

struct MedicineResultView: View {
    let response: MedicineResponse
    @State private var selectedOffer: ProductOffer?

    private var medicineName: String { response.medicine?.name.clean ?? response.query }
    private var details: String {
        [response.medicine?.activeIngredient.clean, response.medicine?.form.clean, response.medicine?.packageInfo.clean]
            .compactMap { $0 }
            .joined(separator: " • ")
    }

    var body: some View {
        AppScaffold {
            VStack(spacing: 14) {
                PageHeader(title: "İlaç Sonuçları", subtitle: nil, showBack: true)
                ResultChip(text: response.query, status: "AI ile tarandı")
                MedicineSummaryCard(name: medicineName, info: response.medicine, imageURL: response.medicine?.imageURL.clean ?? response.offers.first?.imageURL.clean)
                OfferListCard(title: "İnternet Fiyatları", offers: response.offers, buttonTitle: "Satın Al", accent: ERTheme.blue) { selectedOffer = $0 }
                ExpandableTextCard(title: "Kullanım Talimatı", icon: "doc.text.fill", items: response.usageInstructions)
                ExpandableTextCard(title: "Yan Etkiler", icon: "exclamationmark.triangle.fill", items: response.sideEffects, linkText: "Tüm yan etkileri gör")
                if !response.warnings.isEmpty { ExpandableTextCard(title: "Önemli Uyarılar", icon: "shield.lefthalf.filled", items: response.warnings) }
                DisclaimerView(text: response.disclaimer ?? "Doktor tavsiyesi değildir. Sağlık durumunuzla ilgili kararlar için doktorunuza veya eczacınıza danışınız.")
                SourcesView(sources: response.sources)
                PDFShareButton(title: "WhatsApp'ta PDF Paylaş", report: .medicine(response))
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
        .fullScreenCover(item: $selectedOffer) { offer in
            PurchaseScreen(title: "Satın Al", productName: medicineName, subtitle: details.isEmpty ? "İlaç fiyat bilgisi" : details, offers: response.offers, initialOffer: offer, kind: .medicine)
        }
    }
}

struct LabelResultView: View {
    let response: LabelResponse
    @EnvironmentObject private var compareBasket: CompareBasketStore
    @State private var selectedOffer: ProductOffer?

    private var productTitle: String { response.product?.productName.clean ?? response.query }

    var body: some View {
        AppScaffold {
            VStack(spacing: 14) {
                PageHeader(title: "Etiket Karşılaştır", subtitle: "AI ile ürün bilgisi ve fiyat karşılaştırma", showBack: true)
                LabelSummaryCard(product: response.product, fallback: productTitle, imageURL: response.product?.imageURL.clean ?? response.offers.first?.imageURL.clean)
                CompareToggleCard(
                    isSelected: compareBasket.contains(response: response),
                    title: productTitle,
                    action: { compareBasket.toggle(response: response) }
                )
                OfferListCard(title: "Fiyat Karşılaştırması", offers: response.offers, buttonTitle: nil, accent: ERTheme.emerald, highlightBest: true) { selectedOffer = $0 }
                if let best = response.offers.first { BestPriceCard(offer: best) { selectedOffer = best } }
                ExpandableTextCard(title: "Alışveriş Tavsiyeleri", icon: "lightbulb.fill", items: response.suggestions)
                SourcesView(sources: response.sources)
                PDFShareButton(title: "WhatsApp'ta PDF Paylaş", report: .label(response))
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
        .fullScreenCover(item: $selectedOffer) { offer in
            PurchaseScreen(title: "Siteye Git", productName: productTitle, subtitle: response.product?.description.clean ?? "Ürün fiyat karşılaştırması", offers: response.offers, initialOffer: offer, kind: .label)
        }
    }
}

// MARK: - Purchase Full Screen

enum PurchaseKind { case medicine, label }

struct PurchaseScreen: View {
    let title: String
    let productName: String
    let subtitle: String
    let offers: [ProductOffer]
    let kind: PurchaseKind
    @State private var selected: ProductOffer
    @Environment(\.dismiss) private var dismiss

    init(title: String, productName: String, subtitle: String, offers: [ProductOffer], initialOffer: ProductOffer, kind: PurchaseKind) {
        self.title = title
        self.productName = productName
        self.subtitle = subtitle
        self.offers = offers.isEmpty ? [initialOffer] : offers
        self.kind = kind
        _selected = State(initialValue: initialOffer)
    }

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    CircleIcon(systemName: "bag.fill", color: ERTheme.blue, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(ERTheme.navy)
                        Text("Fiyat ve link bilgisi")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(ERTheme.muted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundColor(ERTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.92))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)
                .padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        PurchaseProductCard(productName: productName, subtitle: subtitle, kind: kind, imageURL: selected.imageURL)

                        VStack(spacing: 0) {
                            ForEach(offers) { offer in
                                PurchaseRow(offer: offer, selected: offer == selected) { selected = offer }
                                if offer.id != offers.last?.id { Divider().padding(.leading, 64) }
                            }
                        }
                        .padding(8)
                        .background(.white.opacity(0.94))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(ERTheme.lightStroke.opacity(0.8), lineWidth: 1))
                        .softShadow()

                        HStack(spacing: 7) {
                            Image(systemName: "info.circle")
                            Text(kind == .medicine ? "Fiyatlar bilgilendirme amaçlıdır. Satın almadan önce site ve eczane bilgisini kontrol edin." : "Fiyatlar anlık değişebilir. Satın almadan önce stok, kargo ve satıcı bilgisini kontrol edin.")
                            Spacer()
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(ERTheme.muted)

                        if kind == .medicine {
                            DisclaimerView(text: "Doktor tavsiyesi değildir. İlacı kullanmadan önce prospektüsü okuyun ve doktor/eczacı görüşü alın.")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button { openURL(selected.url) } label: {
                    Label("Siteye Git", systemImage: "arrow.up.right.square.fill")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(LinearGradient(colors: [ERTheme.blue, Color(red: 0.0, green: 0.25, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Button { dismiss() } label: {
                    Text("Kapat")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(ERTheme.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ERTheme.blue.opacity(0.16), lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 5)
            .background(LinearGradient(colors: [.clear, .white.opacity(0.96)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        }
    }
}

// MARK: - Shared Screen Structure

struct AppScaffold<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppBackground().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    content()
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationBarHidden(true)
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            ERTheme.background
            GeometryReader { proxy in
                ZStack {
                    ForEach(0..<5) { i in
                        Circle()
                            .stroke(ERTheme.blue.opacity(0.035), lineWidth: 1)
                            .frame(width: CGFloat(150 + i * 96), height: CGFloat(150 + i * 96))
                            .position(x: proxy.size.width / 2, y: 72 + CGFloat(i * 6))
                    }
                    Circle().fill(ERTheme.cyan.opacity(0.35)).frame(width: 9, height: 9).position(x: proxy.size.width * 0.83, y: 95)
                    Circle().fill(ERTheme.blue.opacity(0.35)).frame(width: 7, height: 7).position(x: proxy.size.width * 0.18, y: 142)
                    WaveDots()
                        .stroke(ERTheme.blue.opacity(0.07), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 8]))
                        .frame(height: 220)
                        .position(x: proxy.size.width / 2, y: proxy.size.height - 160)
                }
            }
        }
    }
}

struct WaveDots: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<14 {
            let y = rect.minY + CGFloat(i) * 13
            path.move(to: CGPoint(x: rect.minX - 15, y: y + sin(CGFloat(i) * 0.7) * 12))
            path.addCurve(
                to: CGPoint(x: rect.maxX + 20, y: y + 26),
                control1: CGPoint(x: rect.width * 0.28, y: y - 34),
                control2: CGPoint(x: rect.width * 0.72, y: y + 62)
            )
        }
        return path
    }
}

// MARK: - Header / Tab

struct BrandHeader: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 5 : 8) {
            RadarLogo()
                .frame(width: compact ? 52 : 68, height: compact ? 52 : 68)
            Text("EtiketRadar")
                .font(.system(size: compact ? 26 : 33, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [ERTheme.navy, ERTheme.blue], startPoint: .leading, endPoint: .trailing))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text("Akıllı fiyat ve ürün asistanı")
                .font(.system(size: compact ? 12 : 15, weight: .semibold))
                .foregroundColor(ERTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PageHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String?
    var showBack: Bool = false
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if showBack {
                    HeaderButton(systemName: "arrow.left") { (onBack ?? { dismiss() })() }
                } else {
                    Spacer().frame(width: 44, height: 44)
                }
                Spacer()
                HeaderButton(systemName: "bell") {}
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(ERTheme.emerald).frame(width: 8, height: 8).offset(x: -4, y: 4)
                    }
            }

            Text(title)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(ERTheme.navy)
                .minimumScaleFactor(0.70)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ERTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }
}

struct HeaderButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(ERTheme.navy)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .softShadow(.black, opacity: 0.05, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }
}

struct BottomTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .bold))
                        Text(tab.title)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Circle()
                            .fill(selectedTab == tab ? ERTheme.blue : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .foregroundColor(selectedTab == tab ? ERTheme.blue : ERTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.9), lineWidth: 1))
        .softShadow(.black, opacity: 0.08, radius: 17, y: 8)
    }
}

// MARK: - Cards

enum HomeVisualType { case tag, medicine }
enum FeatureVisualType { case keyboard, medicineScan, tagScan }

struct HomeActionCard: View {
    let title: String
    let subtitle: String
    let systemIcon: String
    let gradient: LinearGradient
    let accent: Color
    let visual: HomeVisualType

    var body: some View {
        ZStack {
            gradient
            WaveDots()
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 7]))
                .offset(y: 48)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    CircleIcon(systemName: systemIcon, color: accent, size: 48, foreground: .white)
                    Spacer(minLength: 2)
                    Text(title)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(2)
                    CircleArrow()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    switch visual {
                    case .tag: BarcodeTagArt()
                    case .medicine: CapsuleArt()
                    }
                }
                .frame(width: 122, height: 122)
                .padding(.trailing, 2)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 212)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.26), lineWidth: 1))
        .softShadow(accent, opacity: 0.18, radius: 18, y: 10)
    }
}

struct FeatureCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient
    let accent: Color
    let visual: FeatureVisualType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                gradient
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        CircleIcon(systemName: icon, color: accent, size: 46, foreground: .white)
                        Spacer(minLength: 2)
                        Text(title)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(subtitle)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                            .lineLimit(2)
                        CircleArrow(size: 42)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Group {
                        switch visual {
                        case .keyboard: KeyboardArt()
                        case .medicineScan: MedicineScanArt()
                        case .tagScan: BarcodeTagArt()
                        }
                    }
                    .frame(width: 122, height: 118)
                }
                .padding(15)
            }
            .frame(maxWidth: .infinity, minHeight: 176, maxHeight: 194)
            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.26), lineWidth: 1))
            .softShadow(accent, opacity: 0.17, radius: 17, y: 10)
        }
        .buttonStyle(.plain)
    }
}

struct InfoPanel: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(ERTheme.blue)
                .frame(width: 48, height: 48)
                .background(ERTheme.blue.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ERTheme.muted)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(ERTheme.lightStroke.opacity(0.7), lineWidth: 1))
        .softShadow(.black, opacity: 0.05, radius: 12, y: 7)
    }
}

// MARK: - Result Components

struct ResultChip: View {
    let text: String
    let status: String

    var body: some View {
        HStack(spacing: 10) {
            CircleIcon(systemName: "tag.fill", color: ERTheme.blue, size: 38, foreground: .white)
            Text(text)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(ERTheme.navy)
                .lineLimit(1)
            Spacer()
            Label(status, systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundColor(ERTheme.blue)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.88))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(ERTheme.lightStroke.opacity(0.8), lineWidth: 1))
    }
}

struct MedicineSummaryCard: View {
    let name: String
    let info: MedicineInfo?
    let imageURL: String?
    @State private var previewImageURL: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    if let imageURL {
                        ProductThumbnail(url: imageURL, size: 96, fallback: "Rx")
                            .onTapGesture { previewImageURL = imageURL }
                    } else {
                        MedicineBoxArt(name: name)
                            .frame(width: 112, height: 96)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(name)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                    Label("AI ile algılandı", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundColor(ERTheme.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(ERTheme.cyan.opacity(0.13))
                        .clipShape(Capsule())
                    Text("Etkin madde: \(info?.activeIngredient.clean ?? "Belirtilmedi")")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.86))
                        .lineLimit(1)
                    Text("Kutu: \(info?.packageInfo.clean ?? info?.form.clean ?? "Belirtilmedi")")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.86))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(ERTheme.blueGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.22), lineWidth: 1))
        .sheet(item: Binding(
            get: { previewImageURL.map { ImagePreviewPayload(url: $0) } },
            set: { _ in previewImageURL = nil }
        )) { payload in
            ImagePreviewSheet(url: payload.url)
        }
    }
}

struct LabelSummaryCard: View {
    let product: LabelProductInfo?
    let fallback: String
    let imageURL: String?
    @State private var previewImageURL: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    if let imageURL {
                        ProductThumbnail(url: imageURL, size: 96, fallback: "Ü")
                            .onTapGesture { previewImageURL = imageURL }
                    } else {
                        ProductImageArt()
                            .frame(width: 112, height: 96)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI ile algılandı", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundColor(ERTheme.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(ERTheme.blue.opacity(0.09))
                        .clipShape(Capsule())
                    FieldLine(label: "Marka", value: product?.brand.clean ?? "-")
                    FieldLine(label: "Model", value: product?.model.clean ?? product?.productName.clean ?? fallback)
                    FieldLine(label: "Açıklama", value: product?.description.clean ?? "Ürün fiyat karşılaştırması")
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(ERTheme.lightStroke.opacity(0.75), lineWidth: 1))
        .softShadow()
        .sheet(item: Binding(
            get: { previewImageURL.map { ImagePreviewPayload(url: $0) } },
            set: { _ in previewImageURL = nil }
        )) { payload in
            ImagePreviewSheet(url: payload.url)
        }
    }
}

struct FieldLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(ERTheme.muted)
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(ERTheme.navy)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
    }
}

struct OfferListCard: View {
    let title: String
    let offers: [ProductOffer]
    let buttonTitle: String?
    let accent: Color
    var highlightBest: Bool = false
    let onTap: (ProductOffer) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(title, systemImage: "tag.fill")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.navy)
                Spacer()
                Image(systemName: "info.circle")
                    .foregroundColor(ERTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if offers.isEmpty {
                Text("Sonuç bulunamadı. Farklı bir arama deneyin.")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(ERTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ForEach(Array(offers.enumerated()), id: \.element.id) { index, offer in
                    OfferRow(
                        offer: offer,
                        rank: index + 1,
                        isBest: highlightBest && index == 0,
                        buttonTitle: buttonTitle,
                        accent: accent,
                        action: { onTap(offer) }
                    )
                    if offer.id != offers.last?.id { Divider().padding(.leading, 48) }
                }
            }
        }
        .background(.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(ERTheme.lightStroke.opacity(0.70), lineWidth: 1))
        .softShadow()
    }
}

struct OfferRow: View {
    let offer: ProductOffer
    let rank: Int
    let isBest: Bool
    let buttonTitle: String?
    let accent: Color
    let action: () -> Void
    @State private var previewImageURL: String?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text("\(rank)")
                    .font(.caption.bold())
                    .foregroundColor(isBest ? .white : ERTheme.muted)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isBest ? ERTheme.emerald : Color(red: 0.92, green: 0.96, blue: 1.0)))
                ProductThumbnail(url: offer.imageURL, size: 48, fallback: String(offer.siteName.prefix(1)).uppercased())
                    .onTapGesture {
                        if let url = offer.imageURL.clean { previewImageURL = url }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.siteName)
                        .font(.system(size: 15.5, weight: .black, design: .rounded))
                        .foregroundColor(ERTheme.navy)
                        .lineLimit(1)
                    Text(offer.note.clean ?? offer.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ERTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isBest {
                    Text("En Uygun")
                        .font(.caption2.bold())
                        .foregroundColor(ERTheme.emerald)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ERTheme.emerald.opacity(0.10))
                        .clipShape(Capsule())
                }
                Text(offer.priceText.cleanOrNil ?? "Fiyat sayfada")
                    .font(.system(size: 15.5, weight: .black, design: .rounded))
                    .foregroundColor(isBest ? ERTheme.emerald : ERTheme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let buttonTitle {
                    Text(buttonTitle)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(accent)
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(ERTheme.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isBest ? ERTheme.emerald.opacity(0.07) : Color.clear)
        }
        .buttonStyle(.plain)
        .sheet(item: Binding(
            get: { previewImageURL.map { ImagePreviewPayload(url: $0) } },
            set: { _ in previewImageURL = nil }
        )) { payload in
            ImagePreviewSheet(url: payload.url)
        }
    }
}

struct ImagePreviewPayload: Identifiable {
    let url: String
    var id: String { url }
}

struct ProductThumbnail: View {
    let url: String?
    var size: CGFloat = 68
    var fallback: String = "Ü"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color(red: 0.92, green: 0.96, blue: 1.0))
            if let cleanURL = url.clean, let remoteURL = URL(string: cleanURL) {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.72)
                    default:
                        Text(fallback)
                            .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                            .foregroundColor(ERTheme.blue)
                    }
                }
            } else {
                Text(fallback)
                    .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.blue)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct ImagePreviewSheet: View {
    let url: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                case .empty:
                    ProgressView().tint(.white)
                default:
                    Text("Görsel yüklenemedi")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.bold())
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                            .background(.white)
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

struct BestPriceCard: View {
    let offer: ProductOffer
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CircleIcon(systemName: "tag.fill", color: ERTheme.emerald, size: 48, foreground: .white)
            VStack(alignment: .leading, spacing: 2) {
                Text("En Uygun Fiyat")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ERTheme.muted)
                Text(offer.priceText.cleanOrNil ?? "Fiyat sayfada")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.emerald)
            }
            Spacer()
            Button(action: action) {
                Label("Siteye Git", systemImage: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(ERTheme.emerald)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(ERTheme.emerald.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(ERTheme.emerald.opacity(0.22), lineWidth: 1))
    }
}

struct ExpandableTextCard: View {
    let title: String
    let icon: String
    let items: [String]
    var linkText: String? = nil
    @State private var isExpanded = false

    private var shownItems: [String] {
        let cleaned = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return ["Bilgi bulunamadı. Kaynakları kontrol edin."] }
        return isExpanded ? cleaned : Array(cleaned.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(ERTheme.navy)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(ERTheme.navy)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shownItems, id: \.self) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Circle().fill(ERTheme.blue).frame(width: 5, height: 5).padding(.top, 6)
                        Text(item)
                            .font(.system(size: 13.2, weight: .medium))
                            .foregroundColor(ERTheme.ink)
                            .lineLimit(isExpanded ? nil : 3)
                    }
                }
                if let linkText, items.count > shownItems.count || !isExpanded {
                    Text(isExpanded ? "Daha az göster" : linkText + "  ›")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(ERTheme.blue)
                        .padding(.top, 2)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                isExpanded.toggle()
                            }
                        }
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(ERTheme.lightStroke.opacity(0.70), lineWidth: 1))
    }
}

struct DisclaimerView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.checkered")
                .foregroundColor(ERTheme.muted)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundColor(ERTheme.muted)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.horizontal, 8)
    }
}

struct SourcesView: View {
    let sources: [SourceLink]

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kaynaklar")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.navy)
                ForEach(sources.prefix(3)) { source in
                    Button { openURL(source.url) } label: {
                        HStack {
                            Text(source.title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(ERTheme.blue)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.bold())
                                .foregroundColor(ERTheme.blue)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(.white.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Purchase Components

struct PurchaseProductCard: View {
    let productName: String
    let subtitle: String
    let kind: PurchaseKind
    let imageURL: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.94, green: 0.97, blue: 1.0))
                if let imageURL {
                    ProductThumbnail(url: imageURL, size: 86, fallback: kind == .medicine ? "Rx" : "Ü")
                } else if kind == .medicine {
                    MedicineBoxArt(name: productName)
                        .padding(10)
                } else {
                    BarcodeTagArt()
                        .padding(10)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 6) {
                Text(productName)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.navy)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ERTheme.muted)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(ERTheme.lightStroke.opacity(0.8), lineWidth: 1))
        .softShadow()
    }
}

struct PurchaseRow: View {
    let offer: ProductOffer
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(String(offer.siteName.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(selected ? ERTheme.blue : ERTheme.emerald)
                    .frame(width: 42, height: 42)
                    .background((selected ? ERTheme.blue : ERTheme.emerald).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.siteName)
                        .font(.system(size: 15.5, weight: .black, design: .rounded))
                        .foregroundColor(ERTheme.navy)
                        .lineLimit(1)
                    Text(offer.note.clean ?? offer.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ERTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(offer.priceText.cleanOrNil ?? "Fiyat sayfada")
                    .font(.system(size: 15.5, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "arrow.up.right.square")
                    .font(.headline.weight(.bold))
                    .foregroundColor(ERTheme.muted)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(selected ? ERTheme.blue.opacity(0.07) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheets / Image Picker

struct ManualSearchSheet: View {
    let title: String
    let placeholder: String
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Color.gray.opacity(0.25)).frame(width: 42, height: 5).padding(.top, 8)
            Text(title)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(ERTheme.navy)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .font(.system(size: 16, weight: .semibold))
                .padding(14)
                .background(Color(red: 0.94, green: 0.97, blue: 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(spacing: 10) {
                Button("Kapat") { dismiss() }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(ERTheme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(ERTheme.blue.opacity(0.18), lineWidth: 1))
                Button("Ara") { onSubmit(text) }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ERTheme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .background(ERTheme.background)
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image.croppedToVisibleScreenAspect())
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

extension UIImage {
    func croppedToVisibleScreenAspect() -> UIImage {
        let normalized = normalizedUp()
        guard let cgImage = normalized.cgImage else { return normalized }
        let screen = UIScreen.main.bounds
        let targetAspect = screen.width / screen.height
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let imageAspect = imageWidth / imageHeight

        let cropRect: CGRect
        if imageAspect > targetAspect {
            let newWidth = imageHeight * targetAspect
            cropRect = CGRect(x: (imageWidth - newWidth) / 2, y: 0, width: newWidth, height: imageHeight)
        } else {
            let newHeight = imageWidth / targetAspect
            cropRect = CGRect(x: 0, y: (imageHeight - newHeight) / 2, width: imageWidth, height: newHeight)
        }

        guard let cropped = cgImage.cropping(to: cropRect.integral) else { return normalized }
        return UIImage(cgImage: cropped, scale: normalized.scale, orientation: .up)
    }

    private func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Utility Views / Illustrations

struct CircleIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 46
    var foreground: Color = .white

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .black))
            .foregroundColor(foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.92)))
            .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
    }
}

struct CircleArrow: View {
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().stroke(.white.opacity(0.38), lineWidth: 1.6))
    }
}

struct RadarLogo: View {
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .trim(from: 0.08, to: 0.84)
                    .stroke(LinearGradient(colors: [ERTheme.blue, ERTheme.cyan], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: CGFloat(5 - i), lineCap: .round))
                    .frame(width: CGFloat(62 - i * 16), height: CGFloat(62 - i * 16))
                    .rotationEffect(.degrees(Double(i) * 13 - 18))
            }
            Circle().fill(ERTheme.blue).frame(width: 8, height: 8)
            Capsule()
                .fill(LinearGradient(colors: [ERTheme.cyan, ERTheme.blue], startPoint: .leading, endPoint: .trailing))
                .frame(width: 42, height: 8)
                .rotationEffect(.degrees(-42))
                .offset(x: 12, y: -12)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(ERTheme.navy)
                .frame(width: 25, height: 25)
                .rotationEffect(.degrees(39))
                .offset(x: 22, y: 18)
                .overlay(Circle().fill(.white).frame(width: 5, height: 5).offset(x: 22, y: 10))
        }
    }
}

struct BarcodeTagArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(red: 0.91, green: 0.96, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 96, height: 118)
                .rotationEffect(.degrees(-12))
                .softShadow(.black, opacity: 0.18, radius: 12, y: 8)
            Circle().stroke(ERTheme.navy.opacity(0.26), lineWidth: 3).frame(width: 14, height: 14).offset(x: 28, y: -42)
            HStack(spacing: 3) {
                ForEach(0..<12) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ERTheme.navy.opacity(0.86))
                        .frame(width: i % 3 == 0 ? 4 : 2, height: CGFloat(48 + (i % 4) * 8))
                }
            }
            .rotationEffect(.degrees(-12))
            .offset(y: 16)
        }
    }
}

struct CapsuleArt: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [ERTheme.emerald, Color(red: 0.83, green: 1.0, blue: 0.96)], startPoint: .top, endPoint: .bottom))
                .frame(width: 54, height: 114)
                .rotationEffect(.degrees(38))
                .softShadow(ERTheme.emerald, opacity: 0.22, radius: 12, y: 7)
            Capsule()
                .fill(.white.opacity(0.92))
                .frame(width: 54, height: 58)
                .rotationEffect(.degrees(38))
                .offset(x: -22, y: 22)
            Circle()
                .fill(.white.opacity(0.92))
                .frame(width: 64, height: 64)
                .overlay(Rectangle().fill(ERTheme.muted.opacity(0.18)).frame(width: 48, height: 2).rotationEffect(.degrees(18)))
                .offset(x: 36, y: 38)
        }
    }
}

struct KeyboardArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.22))
                .frame(width: 118, height: 48)
                .offset(y: -36)
            Text("İlaç adı...")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .offset(x: -8, y: -36)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .offset(x: 42, y: -36)
            VStack(spacing: 4) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 4) {
                        ForEach(0..<5) { _ in
                            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.72)).frame(width: 17, height: 13)
                        }
                    }
                }
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.82)).frame(width: 76, height: 15)
            }
            .rotationEffect(.degrees(-8))
            .offset(y: 30)
        }
    }
}

struct MedicineScanArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.94))
                .frame(width: 104, height: 70)
                .softShadow(.black, opacity: 0.16, radius: 10, y: 7)
            VStack(alignment: .leading, spacing: 3) {
                Text("Paracetamol")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.navy)
                Text("500 mg Tablet")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ERTheme.emerald)
                Spacer()
                Text("20 Tablet")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(ERTheme.muted)
            }
            .frame(width: 82, height: 48, alignment: .leading)
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 3)
                    .stroke(ERTheme.cyan, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .position(
                        x: CGFloat(index % 2 == 0 ? 7 : 115),
                        y: CGFloat(index < 2 ? 17 : 101)
                    )
            }
        }
    }
}

struct MedicineBoxArt: View {
    let name: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(red: 0.93, green: 0.97, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                .softShadow(.black, opacity: 0.18, radius: 10, y: 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(name.prefix(18).uppercased())
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.blue)
                    .lineLimit(2)
                Text("Film Tablet")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ERTheme.navy)
                Spacer()
                Text("20 Tablet")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(ERTheme.muted)
            }
            .padding(10)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 75))
                path.addCurve(to: CGPoint(x: 130, y: 45), control1: CGPoint(x: 42, y: 100), control2: CGPoint(x: 90, y: 25))
                path.addLine(to: CGPoint(x: 130, y: 110))
                path.addLine(to: CGPoint(x: 0, y: 110))
                path.closeSubpath()
            }
            .fill(ERTheme.blue.opacity(0.18))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProductImageArt: View {
    var body: some View {
        ZStack {
            Circle().stroke(Color.black.opacity(0.90), lineWidth: 10).frame(width: 70, height: 78).offset(y: 10)
            Circle().fill(Color.black.opacity(0.93)).frame(width: 50, height: 50).offset(x: -31, y: 35)
            Circle().fill(Color.black.opacity(0.93)).frame(width: 50, height: 50).offset(x: 31, y: 35)
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.96)).frame(width: 24, height: 64).offset(x: -47, y: 28)
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.96)).frame(width: 24, height: 64).offset(x: 47, y: 28)
        }
    }
}

// MARK: - Misc

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(ERTheme.blue)
                Text(message)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(ERTheme.navy)
            }
            .padding(20)
            .background(.white.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .softShadow()
        }
    }
}

struct SettingsView: View {
    @Binding var backendBaseURL: String
    @Binding var appApiKey: String

    var body: some View {
        AppScaffold {
            VStack(spacing: 14) {
                PageHeader(title: "Ayarlar", subtitle: nil, showBack: false)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Backend")
                        .font(.headline.weight(.black))
                        .foregroundColor(ERTheme.navy)
                    TextField("Backend URL", text: $backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(12)
                        .background(Color(red: 0.94, green: 0.97, blue: 1.0))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    SecureField("Uygulama API anahtarı", text: $appApiKey)
                        .padding(12)
                        .background(Color(red: 0.94, green: 0.97, blue: 1.0))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Tavily ve Gemini anahtarları iPhone içine yazılmaz; sadece Vercel Environment Variables içinde tutulur.")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(ERTheme.muted)
                }
                .padding(16)
                .background(.white.opacity(0.90))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var historyStore: SearchHistoryStore

    var body: some View {
        AppScaffold {
            VStack(spacing: 14) {
                PageHeader(title: "Geçmiş", subtitle: "Son aramalarına tekrar girmeden dön", showBack: false)
                if historyStore.items.isEmpty {
                    EmptyStateView(
                        icon: "clock.badge.questionmark",
                        title: "Henüz arama yok",
                        text: "Etiket veya ilaç araması yaptığında sonuçlar burada saklanacak."
                    )
                } else {
                    HStack {
                        Text("\(historyStore.items.count) kayıt")
                            .font(.caption.weight(.bold))
                            .foregroundColor(ERTheme.muted)
                        Spacer()
                        Button(role: .destructive) {
                            historyStore.clear()
                        } label: {
                            Label("Aramaları Temizle", systemImage: "trash")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .padding(.horizontal, 4)

                    ForEach(historyStore.items) { item in
                        NavigationLink {
                            if let label = item.label {
                                LabelResultView(response: label)
                            } else if let medicine = item.medicine {
                                MedicineResultView(response: medicine)
                            }
                        } label: {
                            HistoryResultRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
    }
}

struct CompareView: View {
    @EnvironmentObject private var compareBasket: CompareBasketStore

    var body: some View {
        AppScaffold {
            VStack(spacing: 14) {
                PageHeader(title: "Kıyasla", subtitle: "Seçtiğin ürünleri özellik ve fiyatla karşılaştır", showBack: false)
                if compareBasket.items.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "Karşılaştırma sepeti boş",
                        text: "Etiket sonuçlarında tik işaretine dokunarak ürünleri buraya ekleyebilirsin."
                    )
                } else {
                    HStack {
                        Text("\(compareBasket.items.count) ürün seçildi")
                            .font(.caption.weight(.bold))
                            .foregroundColor(ERTheme.muted)
                        Spacer()
                        Button(role: .destructive) { compareBasket.clear() } label: {
                            Label("Sepeti Temizle", systemImage: "trash")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .padding(.horizontal, 4)

                    ComparisonSummaryTable(items: compareBasket.items)
                    ForEach(compareBasket.items) { item in
                        CompareItemCard(item: item) {
                            compareBasket.remove(item)
                        }
                    }
                    PDFShareButton(title: "Karşılaştırmayı PDF Paylaş", report: .compare(compareBasket.items))
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .black))
                .foregroundColor(ERTheme.blue)
                .frame(width: 84, height: 84)
                .background(.white.opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            Text(title)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundColor(ERTheme.navy)
                .multilineTextAlignment(.center)
            Text(text)
                .font(.callout.weight(.semibold))
                .foregroundColor(ERTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct HistoryResultRow: View {
    let item: SearchHistoryItem

    var body: some View {
        HStack(spacing: 12) {
            CircleIcon(systemName: item.kind == "medicine" ? "capsule.fill" : "tag.fill", color: item.kind == "medicine" ? ERTheme.emerald : ERTheme.blue, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.kind == "medicine" ? "İlaç" : "Etiket")
                    .font(.caption.bold())
                    .foregroundColor(ERTheme.muted)
                Text(item.title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.navy)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.subtitle)
                    Text("•")
                    Text(item.date, style: .date)
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(ERTheme.muted)
                .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(ERTheme.muted)
        }
        .padding(13)
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(ERTheme.lightStroke.opacity(0.72), lineWidth: 1))
        .softShadow(.black, opacity: 0.05, radius: 12, y: 7)
    }
}

struct CompareToggleCard: View {
    let isSelected: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(isSelected ? ERTheme.emerald : ERTheme.muted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isSelected ? "Karşılaştırma sepetinde" : "Karşılaştırmaya ekle")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(ERTheme.navy)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ERTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "square.split.2x2.fill")
                    .foregroundColor(ERTheme.blue)
            }
            .padding(13)
            .background(.white.opacity(0.90))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke((isSelected ? ERTheme.emerald : ERTheme.lightStroke).opacity(0.72), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ComparisonSummaryTable: View {
    let items: [CompareItem]

    private var rows: [(String, [String])] {
        let keys = Array(Set(items.flatMap { $0.specs.keys })).sorted()
        let base = [
            ("En iyi fiyat", items.map(\.bestPrice)),
            ("En iyi mağaza", items.map(\.bestStore))
        ]
        return base + keys.prefix(8).map { key in
            (key, items.map { $0.specs[key] ?? "-" })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Özellik Tablosu")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(ERTheme.navy)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        tableCell("Özellik", width: 118, isHeader: true)
                        ForEach(items) { item in
                            tableCell(item.title, width: 132, isHeader: true)
                        }
                    }
                    ForEach(rows, id: \.0) { row in
                        HStack(spacing: 0) {
                            tableCell(row.0, width: 118, isHeader: true)
                            ForEach(Array(row.1.enumerated()), id: \.offset) { _, value in
                                tableCell(value, width: 132, isHeader: false)
                            }
                        }
                    }
                }
            }
        }
        .padding(13)
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(ERTheme.lightStroke.opacity(0.72), lineWidth: 1))
    }

    private func tableCell(_ text: String, width: CGFloat, isHeader: Bool) -> some View {
        Text(text)
            .font(.system(size: isHeader ? 12.5 : 12, weight: isHeader ? .black : .semibold, design: .rounded))
            .foregroundColor(isHeader ? ERTheme.navy : ERTheme.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 44, alignment: .leading)
            .padding(8)
            .background(isHeader ? ERTheme.blue.opacity(0.06) : Color.white.opacity(0.32))
            .border(ERTheme.lightStroke.opacity(0.45), width: 0.5)
    }
}

struct CompareItemCard: View {
    let item: CompareItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProductThumbnail(url: item.imageURL, size: 64, fallback: "Ü")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(ERTheme.navy)
                    .lineLimit(2)
                Text(item.subtitle.isEmpty ? "Ürün karşılaştırması" : item.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ERTheme.muted)
                    .lineLimit(1)
                Text("\(item.bestStore) • \(item.bestPrice)")
                    .font(.caption.weight(.black))
                    .foregroundColor(ERTheme.emerald)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundColor(ERTheme.muted)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.8))
                    .clipShape(Circle())
            }
        }
        .padding(13)
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(ERTheme.lightStroke.opacity(0.72), lineWidth: 1))
    }
}

enum ShareReport {
    case medicine(MedicineResponse)
    case label(LabelResponse)
    case compare([CompareItem])

    var title: String {
        switch self {
        case .medicine(let response):
            return response.medicine?.name.clean ?? response.query
        case .label(let response):
            return response.product?.productName.clean ?? response.query
        case .compare:
            return "EtiketRadar Karşılaştırma"
        }
    }

    var sections: [(String, [String])] {
        switch self {
        case .medicine(let response):
            return [
                ("İlaç Bilgisi", [
                    "Sorgu: \(response.query)",
                    "Etkin madde: \(response.medicine?.activeIngredient.clean ?? "-")",
                    "Form/Kutu: \(response.medicine?.packageInfo.clean ?? response.medicine?.form.clean ?? "-")"
                ]),
                ("Fiyatlar", response.offers.map { "\($0.siteName): \($0.priceText.clean ?? "Fiyat sayfada") - \($0.url)" }),
                ("Kullanım Talimatı", response.usageInstructions),
                ("Yan Etkiler", response.sideEffects),
                ("Uyarılar", response.warnings),
                ("Kaynaklar", response.sources.map { "\($0.title): \($0.url)" })
            ]
        case .label(let response):
            let specs = (response.product?.specs ?? response.comparisonSpecs ?? [:]).map { "\($0.key): \($0.value)" }.sorted()
            return [
                ("Ürün", [
                    "Sorgu: \(response.query)",
                    "Marka: \(response.product?.brand.clean ?? "-")",
                    "Model: \(response.product?.model.clean ?? "-")",
                    "Açıklama: \(response.product?.description.clean ?? "-")"
                ]),
                ("Fiyatlar", response.offers.map { "\($0.siteName): \($0.priceText.clean ?? "Fiyat sayfada") - \($0.url)" }),
                ("Özellikler", specs.isEmpty ? ["Özellik bulunamadı."] : specs),
                ("Tavsiyeler", response.suggestions),
                ("Kaynaklar", response.sources.map { "\($0.title): \($0.url)" })
            ]
        case .compare(let items):
            let specs = items.flatMap { item in
                item.specs.map { "\(item.title) • \($0.key): \($0.value)" }
            }
            return [
                ("Seçili Ürünler", items.map { "\($0.title): \($0.bestStore) - \($0.bestPrice)" }),
                ("Özellik Karşılaştırması", specs.isEmpty ? ["Özellik bulunamadı."] : specs)
            ]
        }
    }
}

struct PDFShareButton: View {
    let title: String
    let report: ShareReport
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Button {
            do {
                shareURL = try ReportPDFRenderer.makePDF(report: report)
            } catch {
                errorMessage = error.localizedDescription
            }
        } label: {
            Label(title, systemImage: "square.and.arrow.up.fill")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(colors: [ERTheme.emerald, ERTheme.blue], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .sheet(item: Binding(
            get: { shareURL.map { ShareURL(url: $0) } },
            set: { _ in shareURL = nil }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .alert("PDF oluşturulamadı", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum ReportPDFRenderer {
    static func makePDF(report: ShareReport) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 42
            draw("EtiketRadar", x: 42, y: y, width: 510, size: 22, weight: .bold)
            y += 32
            draw(report.title, x: 42, y: y, width: 510, size: 18, weight: .bold)
            y += 34

            for section in report.sections {
                if y > 760 {
                    context.beginPage()
                    y = 42
                }
                draw(section.0, x: 42, y: y, width: 510, size: 15, weight: .bold)
                y += 22
                for item in section.1.prefix(18) {
                    if y > 790 {
                        context.beginPage()
                        y = 42
                    }
                    let used = draw("• \(item)", x: 54, y: y, width: 488, size: 10.8, weight: .regular)
                    y += used + 6
                }
                y += 10
            }
        }

        let safeName = report.title
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .prefix(38)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EtiketRadar-\(safeName).pdf")
        try data.write(to: url, options: [.atomic])
        return url
    }

    @discardableResult
    private static func draw(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 0.03, green: 0.06, blue: 0.18, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let rect = NSString(string: text).boundingRect(
            with: CGSize(width: width, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        NSString(string: text).draw(
            with: CGRect(x: x, y: y, width: width, height: ceil(rect.height) + 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return ceil(rect.height)
    }
}

func openURL(_ string: String) {
    guard let url = URL(string: string), UIApplication.shared.canOpenURL(url) else { return }
    UIApplication.shared.open(url)
}
