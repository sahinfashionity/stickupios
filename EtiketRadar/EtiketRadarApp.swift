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

// MARK: - Models

struct ProductOffer: Identifiable, Codable, Hashable {
    var id = UUID()
    let siteName: String
    let title: String
    let priceText: String
    let url: String
    let note: String?

    enum CodingKeys: String, CodingKey { case siteName, title, priceText, url, note }
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
}

struct LabelResponse: Codable, Hashable {
    let query: String
    let product: LabelProductInfo?
    let offers: [ProductOffer]
    let suggestions: [String]
    let sources: [SourceLink]
}

struct APIErrorResponse: Codable { let error: String }

enum AppTab: String, CaseIterable {
    case home
    case history
    case settings

    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .history: return "Geçmiş"
        case .settings: return "Ayarlar"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - API Client

struct APIClient {
    let baseURL: String
    let apiKey: String

    private func endpoint(_ path: String) throws -> URL {
        var cleaned = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = "https://etiket-radar-backend.vercel.app/" }
        if !cleaned.hasSuffix("/") { cleaned += "/" }
        guard let url = URL(string: cleaned + path) else { throw NSError.userMessage("Backend URL hatalı.") }
        return url
    }

    func medicineSearch(query: String, ocrText: String? = nil) async throws -> MedicineResponse {
        let body: [String: Any] = [
            "query": query,
            "ocrText": ocrText ?? ""
        ]
        return try await post("v1/medicine-search", body: body)
    }

    func labelSearch(query: String, ocrText: String? = nil) async throws -> LabelResponse {
        let body: [String: Any] = [
            "query": query,
            "ocrText": ocrText ?? ""
        ]
        return try await post("v1/label-search", body: body)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = try endpoint(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NSError.userMessage("Sunucudan geçersiz cevap geldi.") }
        guard (200..<300).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw NSError.userMessage(err.error)
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

struct AppTheme {
    static let navy = Color(red: 0.025, green: 0.055, blue: 0.18)
    static let ink = Color(red: 0.06, green: 0.10, blue: 0.26)
    static let muted = Color(red: 0.37, green: 0.44, blue: 0.58)
    static let blue = Color(red: 0.02, green: 0.38, blue: 0.97)
    static let cyan = Color(red: 0.08, green: 0.80, blue: 0.90)
    static let emerald = Color(red: 0.00, green: 0.62, blue: 0.47)
    static let mint = Color(red: 0.08, green: 0.88, blue: 0.68)
    static let cardStroke = Color(red: 0.80, green: 0.88, blue: 1.00)

    static let screenBackground = LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.985, blue: 1.0),
            Color.white,
            Color(red: 0.925, green: 0.97, blue: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let deepBlue = LinearGradient(
        colors: [Color(red: 0.02, green: 0.12, blue: 0.34), Color(red: 0.02, green: 0.32, blue: 0.86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let deepGreen = LinearGradient(
        colors: [Color(red: 0.00, green: 0.38, blue: 0.34), Color(red: 0.10, green: 0.78, blue: 0.64)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func premiumShadow(_ color: Color = .black, opacity: Double = 0.10, radius: CGFloat = 24, y: CGFloat = 14) -> some View {
        shadow(color: color.opacity(opacity), radius: radius, x: 0, y: y)
    }
}

// MARK: - Root

struct RootView: View {
    @AppStorage("backendBaseURL") private var backendBaseURL = "https://etiket-radar-backend.vercel.app/"
    @AppStorage("appApiKey") private var appApiKey = "etiket-radar-123456"
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    NavigationStack { HomeView(client: client) }
                case .history:
                    NavigationStack { HistoryView() }
                case .settings:
                    NavigationStack { SettingsView(backendBaseURL: $backendBaseURL, appApiKey: $appApiKey) }
                }
            }
            .tint(AppTheme.blue)

            PremiumTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
        }
    }

    private var client: APIClient { APIClient(baseURL: backendBaseURL, apiKey: appApiKey) }
}

// MARK: - Home

struct HomeView: View {
    let client: APIClient

    var body: some View {
        PremiumScreen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 30) {
                    HomeBrandHeader()
                        .padding(.top, 18)
                        .padding(.bottom, 10)

                    NavigationLink {
                        LabelLandingView(client: client)
                    } label: {
                        PremiumChoiceCard(
                            title: "Etiket",
                            subtitle: "Ürün fiyatlarını karşılaştır",
                            icon: "tag.fill",
                            gradient: AppTheme.deepBlue,
                            accent: AppTheme.blue
                        ) {
                            BarcodeTagIllustration()
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MedicineLandingView(client: client)
                    } label: {
                        PremiumChoiceCard(
                            title: "İlaç",
                            subtitle: "Fiyat, kullanım ve yan etkiler",
                            icon: "capsule.fill",
                            gradient: AppTheme.deepGreen,
                            accent: AppTheme.emerald
                        ) {
                            CapsuleHeroIllustration()
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 150)
                }
                .padding(.horizontal, 28)
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Medicine Flow

struct MedicineLandingView: View {
    let client: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var showManual = false
    @State private var showCamera = false
    @State private var loadingMessage: String?
    @State private var errorMessage: String?
    @State private var response: MedicineResponse?
    @State private var navigate = false

    var body: some View {
        PremiumScreen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    TallPageHeader(
                        title: "İlaç Asistanı",
                        subtitle: "İlaç bilgilerini hızlıca öğren",
                        logo: .radar,
                        showBack: true,
                        action: { dismiss() }
                    )
                    .padding(.top, 16)

                    Button { showManual = true } label: {
                        FeatureVisualCard(
                            title: "Manuel Ekle",
                            subtitle: "İlacın adını yazarak ara",
                            icon: "keyboard.fill",
                            gradient: AppTheme.deepBlue,
                            accent: AppTheme.blue
                        ) {
                            KeyboardSearchIllustration()
                        }
                    }
                    .buttonStyle(.plain)

                    Button { showCamera = true } label: {
                        FeatureVisualCard(
                            title: "Fotoğraf Çek",
                            subtitle: "Kutunun fotoğrafını çek,\nAI algılasın",
                            icon: "camera.fill",
                            gradient: AppTheme.deepGreen,
                            accent: AppTheme.emerald
                        ) {
                            MedicineScanIllustration()
                        }
                    }
                    .buttonStyle(.plain)

                    SafetyInfoPanel()

                    Spacer(minLength: 150)
                }
                .padding(.horizontal, 28)
            }
            if let loadingMessage { PremiumLoadingOverlay(message: loadingMessage) }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showManual) {
            ManualSearchSheet(title: "İlaç adı yaz", placeholder: "Örn: Majezik 100 mg veya Ofnol S %0.2") { query in
                showManual = false
                Task { await searchMedicine(query: query, ocrText: nil) }
            }
            .presentationDetents([.height(330)])
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker { image in
                showCamera = false
                Task { await handleMedicineImage(image) }
            }
        }
        .alert("Uyarı", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .navigationDestination(isPresented: $navigate) {
            if let response { MedicineResultView(response: response) }
        }
    }

    private func handleMedicineImage(_ image: UIImage) async {
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "İlaç adı boş olamaz."; return }
        do {
            loadingMessage = "İlaç bilgileri aranıyor..."
            response = try await client.medicineSearch(query: trimmed, ocrText: ocrText)
            loadingMessage = nil
            navigate = true
        } catch {
            loadingMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func bestMedicineQuery(from text: String) -> String {
        let lines = text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }

        let ignored = ["KULLAN", "SAKL", "PROSPEKT", "BARKOD", "SERİ", "LOT", "SKT", "ÜRETİM", "TABLET", "ML"]
        let candidate = lines.first { line in
            let upper = line.uppercased()
            return !ignored.contains { upper.contains($0) }
        }
        return candidate ?? text.replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Label Flow

struct LabelLandingView: View {
    let client: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var showManual = false
    @State private var showCamera = false
    @State private var loadingMessage: String?
    @State private var errorMessage: String?
    @State private var response: LabelResponse?
    @State private var navigate = false

    var body: some View {
        PremiumScreen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    TallPageHeader(
                        title: "Etiket Karşılaştır",
                        subtitle: "Mağaza fiyatını internette kontrol et",
                        logo: .radar,
                        showBack: true,
                        action: { dismiss() }
                    )
                    .padding(.top, 16)

                    Button { showCamera = true } label: {
                        FeatureVisualCard(
                            title: "Etiket Fotoğrafı",
                            subtitle: "Raf etiketi veya ürün kutusunu çek",
                            icon: "viewfinder",
                            gradient: AppTheme.deepBlue,
                            accent: AppTheme.blue
                        ) {
                            BarcodeTagIllustration()
                        }
                    }
                    .buttonStyle(.plain)

                    Button { showManual = true } label: {
                        FeatureVisualCard(
                            title: "Manuel Ürün Ara",
                            subtitle: "Marka, model veya barkod yaz",
                            icon: "magnifyingglass",
                            gradient: AppTheme.deepGreen,
                            accent: AppTheme.emerald
                        ) {
                            KeyboardSearchIllustration()
                        }
                    }
                    .buttonStyle(.plain)

                    LabelInfoPanel()
                    Spacer(minLength: 150)
                }
                .padding(.horizontal, 28)
            }
            if let loadingMessage { PremiumLoadingOverlay(message: loadingMessage) }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showManual) {
            ManualSearchSheet(title: "Ürün adı yaz", placeholder: "Örn: Sony WH-CH720N siyah") { query in
                showManual = false
                Task { await searchLabel(query: query, ocrText: nil) }
            }
            .presentationDetents([.height(330)])
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker { image in
                showCamera = false
                Task { await handleLabelImage(image) }
            }
        }
        .alert("Uyarı", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .navigationDestination(isPresented: $navigate) {
            if let response { LabelResultView(response: response) }
        }
    }

    private func handleLabelImage(_ image: UIImage) async {
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "Ürün adı boş olamaz."; return }
        do {
            loadingMessage = "İnternet fiyatları aranıyor..."
            response = try await client.labelSearch(query: trimmed, ocrText: ocrText)
            loadingMessage = nil
            navigate = true
        } catch {
            loadingMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func bestLabelQuery(from text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.prefix(14).joined(separator: " ")
    }
}

// MARK: - Result Views

struct MedicineResultView: View {
    let response: MedicineResponse
    @State private var selectedOffer: ProductOffer?

    private var medName: String { response.medicine?.name?.nilIfEmpty ?? response.query }
    private var formText: String {
        [response.medicine?.activeIngredient, response.medicine?.form, response.medicine?.packageInfo]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: " • ")
    }

    var body: some View {
        PremiumScreen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    CompactPageHeader(title: "İlaç Sonuçları", showBack: true)
                        .padding(.top, 14)

                    RecognizedChip(text: response.query, status: "AI ile tarandı")

                    MedicineHeroResultCard(
                        name: medName,
                        active: response.medicine?.activeIngredient,
                        form: response.medicine?.form,
                        packageInfo: response.medicine?.packageInfo
                    )

                    PriceListCard(
                        title: "İnternet Fiyatları",
                        offers: response.offers,
                        rowButtonTitle: "Satın Al",
                        accent: AppTheme.blue,
                        onTap: { selectedOffer = $0 }
                    )

                    ExpandInfoCard(title: "Kullanım Talimatı", icon: "doc.text.fill", items: response.usageInstructions)
                    ExpandInfoCard(title: "Yan Etkiler", icon: "exclamationmark.triangle.fill", items: response.sideEffects, linkText: "Tüm yan etkileri gör")

                    if !response.warnings.isEmpty {
                        ExpandInfoCard(title: "Önemli Uyarılar", icon: "shield.lefthalf.filled", items: response.warnings)
                    }

                    MedicalDisclaimer(text: response.disclaimer ?? "Doktor tavsiyesi değildir. Sağlık durumunuzla ilgili kararlar için doktorunuza veya eczacınıza danışınız.")
                    SourcesCompact(sources: response.sources)
                    Spacer(minLength: 130)
                }
                .padding(.horizontal, 24)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(item: $selectedOffer) { offer in
            FullScreenPurchaseView(
                title: "Satın Al",
                primaryName: medName,
                subtitle: formText.isEmpty ? "İlaç fiyat bilgisi" : formText,
                offers: response.offers,
                initialOffer: offer,
                productKind: .medicine
            )
        }
    }
}

struct LabelResultView: View {
    let response: LabelResponse
    @State private var selectedOffer: ProductOffer?

    private var productTitle: String { response.product?.productName?.nilIfEmpty ?? response.query }
    private var bestOffer: ProductOffer? { response.offers.first }

    var body: some View {
        PremiumScreen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    CompactPageHeader(title: "Etiket Karşılaştır", showBack: true, subtitle: "AI ile ürün bilgisi ve fiyat karşılaştırma")
                        .padding(.top, 14)

                    LabelProductHeroCard(product: response.product, fallbackTitle: productTitle)

                    PriceListCard(
                        title: "Fiyat Karşılaştırması",
                        offers: response.offers,
                        rowButtonTitle: nil,
                        accent: AppTheme.emerald,
                        highlightBest: true,
                        onTap: { selectedOffer = $0 }
                    )

                    if let bestOffer {
                        BestPriceSummary(offer: bestOffer) { selectedOffer = bestOffer }
                    }

                    ExpandInfoCard(title: "Alışveriş Tavsiyeleri", icon: "lightbulb.fill", items: response.suggestions)
                    SourcesCompact(sources: response.sources)
                    Spacer(minLength: 130)
                }
                .padding(.horizontal, 24)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(item: $selectedOffer) { offer in
            FullScreenPurchaseView(
                title: "Siteye Git",
                primaryName: productTitle,
                subtitle: response.product?.description ?? "Ürün fiyat karşılaştırması",
                offers: response.offers,
                initialOffer: offer,
                productKind: .label
            )
        }
    }
}

// MARK: - Full Screen Purchase

enum PurchaseProductKind { case medicine, label }

struct FullScreenPurchaseView: View {
    let title: String
    let primaryName: String
    let subtitle: String
    let offers: [ProductOffer]
    let productKind: PurchaseProductKind
    @State private var selected: ProductOffer
    @Environment(\.dismiss) private var dismiss

    init(title: String, primaryName: String, subtitle: String, offers: [ProductOffer], initialOffer: ProductOffer, productKind: PurchaseProductKind) {
        self.title = title
        self.primaryName = primaryName
        self.subtitle = subtitle
        self.offers = offers.isEmpty ? [initialOffer] : offers
        self.productKind = productKind
        _selected = State(initialValue: initialOffer)
    }

    var body: some View {
        PremiumScreen {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "bag.fill")
                        .font(.title2.weight(.black))
                        .foregroundColor(AppTheme.blue)
                        .frame(width: 50, height: 50)
                        .background(.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .premiumShadow(AppTheme.blue, opacity: 0.12, radius: 18, y: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(AppTheme.navy)
                        Text("Fiyat ve link bilgisi")
                            .font(.callout.weight(.semibold))
                            .foregroundColor(AppTheme.muted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 50, height: 50)
                            .background(.white.opacity(0.92))
                            .clipShape(Circle())
                            .premiumShadow(.black, opacity: 0.06, radius: 14, y: 6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 18)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        PurchaseProductPanel(name: primaryName, subtitle: subtitle, kind: productKind)

                        VStack(spacing: 0) {
                            ForEach(offers) { offer in
                                PurchaseOfferRow(
                                    offer: offer,
                                    selected: offer == selected,
                                    action: { selected = offer }
                                )
                                if offer.id != offers.last?.id { Divider().padding(.leading, 78) }
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(0.94))
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(AppTheme.cardStroke.opacity(0.85), lineWidth: 1))
                        .premiumShadow(.black, opacity: 0.07, radius: 24, y: 14)

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(AppTheme.muted)
                            Text(productKind == .medicine ? "Fiyatlar bilgilendirme amaçlıdır. Satın almadan önce site ve eczane bilgisini kontrol edin." : "Fiyatlar anlık değişebilir. Satın almadan önce stok, kargo ve satıcı bilgisini kontrol edin.")
                                .font(.footnote.weight(.medium))
                                .foregroundColor(AppTheme.muted)
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        if productKind == .medicine {
                            MedicalDisclaimer(text: "Doktor tavsiyesi değildir. İlacı kullanmadan önce prospektüsü okuyun ve doktor/eczacı görüşü alın.")
                        }

                        Spacer(minLength: 170)
                    }
                    .padding(.horizontal, 24)
                }
            }

            VStack(spacing: 12) {
                Button { openURL(selected.url) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("Siteye Git")
                    }
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(colors: [AppTheme.blue, Color(red: 0.00, green: 0.25, blue: 0.90)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .premiumShadow(AppTheme.blue, opacity: 0.24, radius: 22, y: 12)
                }

                Button { dismiss() } label: {
                    Text("Kapat")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(.white.opacity(0.94))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.blue.opacity(0.16), lineWidth: 1))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, Color.white.opacity(0.96)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

struct PurchaseProductPanel: View {
    let name: String
    let subtitle: String
    let kind: PurchaseProductKind

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.94, green: 0.97, blue: 1.0))
                    .frame(width: 122, height: 122)
                if kind == .medicine {
                    MedicineBoxMini(name: name)
                        .frame(width: 90, height: 100)
                } else {
                    BarcodeTagIllustration()
                        .frame(width: 110, height: 94)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.muted)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(18)
        .background(.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(AppTheme.cardStroke.opacity(0.85), lineWidth: 1))
        .premiumShadow(.black, opacity: 0.07, radius: 22, y: 12)
    }
}

struct PurchaseOfferRow: View {
    let offer: ProductOffer
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(selected ? AppTheme.blue.opacity(0.16) : Color(red: 0.94, green: 0.97, blue: 1.0))
                        .frame(width: 52, height: 52)
                    Text(String(offer.siteName.prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(selected ? AppTheme.blue : AppTheme.emerald)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(offer.siteName)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.navy)
                        .lineLimit(1)
                    Text(offer.note?.nilIfEmpty ?? offer.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                Text(offer.priceText.nilIfEmpty ?? "Fiyat sayfada")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.blue)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right.square")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppTheme.muted)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background(selected ? Color(red: 0.94, green: 0.98, blue: 1.0) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Premium Screens

struct PremiumScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AppTheme.screenBackground.ignoresSafeArea()
            RadarBackground()
                .ignoresSafeArea()
            content()
        }
    }
}

struct RadarBackground: View {
    var body: some View {
        ZStack {
            ForEach(0..<5) { index in
                Circle()
                    .stroke(Color.blue.opacity(0.035), lineWidth: 1)
                    .frame(width: CGFloat(250 + index * 145), height: CGFloat(250 + index * 145))
                    .offset(y: CGFloat(-310 + index * 16))
            }
            Circle().fill(AppTheme.cyan.opacity(0.55)).frame(width: 11, height: 11).offset(x: 140, y: -278)
            Circle().fill(AppTheme.blue.opacity(0.48)).frame(width: 8, height: 8).offset(x: -158, y: -225)
            Circle().fill(AppTheme.emerald.opacity(0.46)).frame(width: 12, height: 12).offset(x: 196, y: 28)
            DottedWave()
                .stroke(AppTheme.blue.opacity(0.09), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 9]))
                .frame(height: 280)
                .offset(y: 360)
        }
    }
}

struct DottedWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0..<18 {
            let y = rect.minY + CGFloat(i) * 13
            path.move(to: CGPoint(x: rect.minX - 20, y: y + sin(CGFloat(i) * 0.7) * 14))
            path.addCurve(
                to: CGPoint(x: rect.maxX + 30, y: y + 34),
                control1: CGPoint(x: rect.width * 0.28, y: y - 40),
                control2: CGPoint(x: rect.width * 0.70, y: y + 76)
            )
        }
        return path
    }
}

struct HomeBrandHeader: View {
    var body: some View {
        VStack(spacing: 14) {
            RadarLogo()
                .frame(width: 112, height: 112)
            Text("EtiketRadar")
                .font(.system(size: 51, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [AppTheme.navy, AppTheme.blue], startPoint: .leading, endPoint: .trailing)
                )
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("Akıllı fiyat ve ürün asistanı")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

enum HeaderLogoStyle { case radar, none }

struct TallPageHeader: View {
    let title: String
    let subtitle: String
    let logo: HeaderLogoStyle
    let showBack: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                if showBack { RoundIconButton(systemName: "arrow.left", action: action) }
                Spacer()
                NotificationButton()
            }
            if logo == .radar { RadarLogo().frame(width: 98, height: 98) }
            Text(title)
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [AppTheme.navy, AppTheme.blue], startPoint: .leading, endPoint: .trailing))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CompactPageHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var showBack: Bool
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .center) {
            if showBack { RoundIconButton(systemName: "arrow.left", action: { dismiss() }) }
            Spacer()
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(AppTheme.muted)
                        .lineLimit(2)
                }
            }
            Spacer()
            NotificationButton()
        }
    }
}

struct RoundIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.navy)
                .frame(width: 58, height: 58)
                .background(.white.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .premiumShadow(.black, opacity: 0.06, radius: 15, y: 8)
        }
    }
}

struct NotificationButton: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.navy)
                .frame(width: 58, height: 58)
                .background(.white.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .premiumShadow(.black, opacity: 0.06, radius: 15, y: 8)
            Circle()
                .fill(AppTheme.emerald)
                .frame(width: 11, height: 11)
                .offset(x: 1, y: -1)
        }
    }
}

struct PremiumTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 25, weight: .bold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Circle()
                            .fill(selectedTab == tab ? AppTheme.blue : .clear)
                            .frame(width: 6, height: 6)
                    }
                    .foregroundColor(selectedTab == tab ? AppTheme.blue : AppTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 35).stroke(Color.white.opacity(0.85), lineWidth: 1))
        .premiumShadow(.black, opacity: 0.08, radius: 22, y: 12)
    }
}

// MARK: - Cards

struct PremiumChoiceCard<Visual: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient
    let accent: Color
    @ViewBuilder let visual: () -> Visual

    var body: some View {
        ZStack {
            gradient
            DottedWave()
                .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 8]))
                .offset(y: 66)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(accent.opacity(0.85)))
                        .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
                    Spacer()
                    Text(title)
                        .font(.system(size: 45, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 62, height: 62)
                        .background(Circle().stroke(.white.opacity(0.38), lineWidth: 2))
                }
                .padding(24)
                Spacer(minLength: 0)
                visual()
                    .frame(width: 230, height: 210)
                    .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 270)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white.opacity(0.28), lineWidth: 1.4))
        .premiumShadow(accent, opacity: 0.22, radius: 24, y: 16)
    }
}

struct FeatureVisualCard<Visual: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient
    let accent: Color
    @ViewBuilder let visual: () -> Visual

    var body: some View {
        ZStack {
            gradient
            DottedWave()
                .stroke(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 8]))
                .offset(y: 74)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 70)
                        .background(Circle().fill(accent.opacity(0.88)))
                        .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
                    Spacer()
                    Text(title)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.83))
                        .lineLimit(2)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 58, height: 58)
                        .background(Circle().stroke(.white.opacity(0.38), lineWidth: 2))
                }
                .padding(22)
                Spacer(minLength: 0)
                visual()
                    .frame(width: 235, height: 205)
                    .padding(.trailing, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white.opacity(0.30), lineWidth: 1.3))
        .premiumShadow(accent, opacity: 0.20, radius: 24, y: 16)
    }
}

struct SafetyInfoPanel: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 28, weight: .black))
                .foregroundColor(AppTheme.blue)
                .frame(width: 62, height: 62)
                .background(AppTheme.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Güvenliğiniz önceliğimiz")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                Text("Fiyat, kullanım talimatı ve yan etkiler gibi detaylara ulaşabilirsiniz.")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(AppTheme.muted)
            }
            Spacer()
        }
        .padding(18)
        .background(.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(AppTheme.cardStroke.opacity(0.75), lineWidth: 1))
        .premiumShadow(.black, opacity: 0.06, radius: 20, y: 12)
    }
}

struct LabelInfoPanel: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "cart.badge.questionmark")
                .font(.system(size: 28, weight: .black))
                .foregroundColor(AppTheme.emerald)
                .frame(width: 62, height: 62)
                .background(AppTheme.emerald.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Mağazada hızlı kontrol")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                Text("Elektronik, market, kozmetik ve mağaza ürünlerinde internet fiyatlarını karşılaştırın.")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(AppTheme.muted)
            }
            Spacer()
        }
        .padding(18)
        .background(.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(AppTheme.cardStroke.opacity(0.75), lineWidth: 1))
        .premiumShadow(.black, opacity: 0.06, radius: 20, y: 12)
    }
}

// MARK: - Result Components

struct RecognizedChip: View {
    let text: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(AppTheme.blue))
            Text(text)
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.navy)
                .lineLimit(1)
            Spacer()
            Label(status, systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundColor(AppTheme.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white.opacity(0.86))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppTheme.cardStroke.opacity(0.9), lineWidth: 1))
        .premiumShadow(.black, opacity: 0.05, radius: 16, y: 8)
    }
}

struct MedicineHeroResultCard: View {
    let name: String
    let active: String?
    let form: String?
    let packageInfo: String?

    var body: some View {
        ZStack {
            AppTheme.deepBlue
            HStack(spacing: 18) {
                MedicineBoxIllustration(name: name, form: form ?? "Film Tablet")
                    .frame(width: 205, height: 160)
                VStack(alignment: .leading, spacing: 12) {
                    Text(name)
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                    Label("AI ile algılandı", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundColor(AppTheme.mint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.mint.opacity(0.18))
                        .clipShape(Capsule())
                    if let active = active?.nilIfEmpty {
                        Text("Etkin madde: \(active)")
                            .font(.callout.weight(.semibold))
                            .foregroundColor(.white.opacity(0.88))
                    }
                    if let packageInfo = packageInfo?.nilIfEmpty {
                        Text("Kutu içeriği: \(packageInfo)")
                            .font(.callout.weight(.semibold))
                            .foregroundColor(.white.opacity(0.88))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, minHeight: 215)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.28), lineWidth: 1))
        .premiumShadow(AppTheme.blue, opacity: 0.20, radius: 26, y: 15)
    }
}

struct LabelProductHeroCard: View {
    let product: LabelProductInfo?
    let fallbackTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Etiket Karşılaştır")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.navy)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("AI ile ürün bilgisi ve fiyat karşılaştırma")
                .font(.callout.weight(.semibold))
                .foregroundColor(AppTheme.muted)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 18) {
                HeadphoneIllustration()
                    .frame(width: 185, height: 185)
                    .background(Color(red: 0.96, green: 0.98, blue: 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Label("AI ile algılandı", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundColor(AppTheme.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(AppTheme.blue.opacity(0.10))
                        .clipShape(Capsule())
                    InfoLine(label: "Marka", value: product?.brand?.nilIfEmpty ?? "-", big: true)
                    InfoLine(label: "Model", value: product?.model?.nilIfEmpty ?? fallbackTitle, big: true)
                    InfoLine(label: "Açıklama", value: product?.description?.nilIfEmpty ?? product?.productName?.nilIfEmpty ?? "Ürün bilgisi", big: false)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .background(.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(AppTheme.cardStroke.opacity(0.85), lineWidth: 1))
        .premiumShadow(.black, opacity: 0.07, radius: 24, y: 14)
    }
}

struct InfoLine: View {
    let label: String
    let value: String
    let big: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label + ":")
                .font(.caption.weight(.bold))
                .foregroundColor(AppTheme.muted)
            Text(value)
                .font(.system(size: big ? 19 : 15, weight: .black, design: .rounded))
                .foregroundColor(AppTheme.navy)
                .lineLimit(big ? 1 : 2)
                .minimumScaleFactor(0.75)
        }
    }
}

struct PriceListCard: View {
    let title: String
    let offers: [ProductOffer]
    let rowButtonTitle: String?
    let accent: Color
    var highlightBest = false
    let onTap: (ProductOffer) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "tag.fill")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.blue))
                Text(title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(highlightBest ? .white : AppTheme.navy)
                Spacer()
                if !offers.isEmpty {
                    Text("\(offers.count) sonuç")
                        .font(.caption.bold())
                        .foregroundColor(highlightBest ? .white.opacity(0.75) : AppTheme.muted)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .background(highlightBest ? AnyShapeStyle(AppTheme.deepBlue) : AnyShapeStyle(Color.clear))

            if offers.isEmpty {
                Text("Sonuç bulunamadı. Daha net marka/model, doz veya barkod bilgisiyle tekrar deneyin.")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(offers.enumerated()), id: \.element.id) { index, offer in
                        PriceRow(
                            rank: index + 1,
                            offer: offer,
                            isBest: index == 0 && highlightBest,
                            buttonTitle: rowButtonTitle,
                            action: { onTap(offer) }
                        )
                        if index < offers.count - 1 { Divider().padding(.leading, 74) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }

            if !offers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkerboard")
                        .foregroundColor(AppTheme.muted)
                    Text("Fiyatlar bilgilendirme amaçlıdır. Değişiklik gösterebilir.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppTheme.muted)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
        .background(.white.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(AppTheme.cardStroke.opacity(0.82), lineWidth: 1))
        .premiumShadow(.black, opacity: 0.06, radius: 22, y: 12)
    }
}

struct PriceRow: View {
    let rank: Int
    let offer: ProductOffer
    let isBest: Bool
    let buttonTitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Text("\(rank)")
                    .font(.headline.bold())
                    .foregroundColor(isBest ? .white : AppTheme.navy)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(isBest ? AppTheme.emerald : Color(red: 0.91, green: 0.95, blue: 1.0)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(offer.siteName)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.navy)
                        .lineLimit(1)
                    Text(offer.note?.nilIfEmpty ?? offer.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                if isBest {
                    Text("En Uygun")
                        .font(.caption.bold())
                        .foregroundColor(AppTheme.emerald)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.emerald.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(offer.priceText.nilIfEmpty ?? "Link")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(isBest ? AppTheme.emerald : AppTheme.navy)
                    .lineLimit(1)
                if let buttonTitle {
                    Text(buttonTitle)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(AppTheme.blue)
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.headline.bold())
                        .foregroundColor(AppTheme.muted)
                }
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 12)
            .background(isBest ? AppTheme.emerald.opacity(0.07) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct BestPriceSummary: View {
    let offer: ProductOffer
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "tag.fill")
                .font(.title2.bold())
                .foregroundColor(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(AppTheme.emerald.opacity(0.85)))
            VStack(alignment: .leading, spacing: 5) {
                Text("En Uygun Fiyat")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.emerald)
                Text(offer.priceText.nilIfEmpty ?? offer.siteName)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.emerald)
            }
            Spacer()
            Button(action: action) {
                Label("Siteye Git", systemImage: "arrow.up.right.square")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(AppTheme.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(18)
        .background(AppTheme.emerald.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(AppTheme.emerald.opacity(0.32), lineWidth: 1))
    }
}

struct ExpandInfoCard: View {
    let title: String
    let icon: String
    let items: [String]
    var linkText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppTheme.blue))
                Text(title)
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.headline.bold())
                    .foregroundColor(AppTheme.navy)
            }
            if items.isEmpty {
                Text("Güvenilir kaynaklardan yeterli bilgi alınamadı.")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(AppTheme.muted)
            } else {
                ForEach(items.prefix(5), id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(AppTheme.blue).frame(width: 6, height: 6).padding(.top, 7)
                        Text(item)
                            .font(.callout.weight(.medium))
                            .foregroundColor(AppTheme.ink)
                    }
                }
            }
            if let linkText {
                HStack(spacing: 8) {
                    Text(linkText)
                    Image(systemName: "chevron.right")
                }
                .font(.callout.bold())
                .foregroundColor(AppTheme.blue)
            }
        }
        .padding(18)
        .background(.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(AppTheme.cardStroke.opacity(0.80), lineWidth: 1))
        .premiumShadow(.black, opacity: 0.05, radius: 18, y: 10)
    }
}

struct MedicalDisclaimer: View {
    let text: String

    var body: some View {
        VStack(spacing: 4) {
            Label("Doktor tavsiyesi değildir.", systemImage: "shield.checkerboard")
                .font(.footnote.bold())
                .foregroundColor(AppTheme.muted)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(AppTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

struct SourcesCompact: View {
    let sources: [SourceLink]

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Kaynaklar", systemImage: "link")
                    .font(.headline.bold())
                    .foregroundColor(AppTheme.navy)
                ForEach(sources.prefix(4)) { source in
                    Button { openURL(source.url) } label: {
                        HStack(spacing: 8) {
                            Text(source.title)
                                .font(.callout.weight(.semibold))
                                .foregroundColor(AppTheme.blue)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(AppTheme.blue)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(.white.opacity(0.84))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppTheme.cardStroke.opacity(0.75), lineWidth: 1))
        }
    }
}

// MARK: - Sheets / Utility UI

struct ManualSearchSheet: View {
    let title: String
    let placeholder: String
    let onSearch: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.navy)
                    Text("Tek satır yaz, sonuçları hemen ara.")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(AppTheme.muted)
                }
                Spacer()
                Button("Kapat") { dismiss() }
                    .font(.headline.bold())
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.muted)
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .padding(17)
            .background(Color(red: 0.94, green: 0.97, blue: 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.cardStroke.opacity(0.90), lineWidth: 1))

            Button { onSearch(text) } label: {
                Text("Ara")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(17)
                    .background(AppTheme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Spacer()
        }
        .padding(24)
        .background(AppTheme.screenBackground)
    }
}

struct PremiumLoadingOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.20).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.35)
                Text(message)
                    .font(.headline.bold())
                    .foregroundColor(AppTheme.navy)
            }
            .padding(26)
            .background(.white.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .premiumShadow(.black, opacity: 0.15, radius: 24, y: 12)
        }
    }
}

struct SettingsView: View {
    @Binding var backendBaseURL: String
    @Binding var appApiKey: String

    var body: some View {
        PremiumScreen {
            Form {
                Section("Backend") {
                    TextField("Backend URL", text: $backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Uygulama API anahtarı", text: $appApiKey)
                }
                Section("Ucuz altyapı") {
                    Text("Tavily ve Gemini anahtarları iPhone içine yazılmaz. Bunlar sadece Vercel Environment Variables içinde tutulur.")
                    Text("Uygulama OCR işlemini cihazda yapar; backend Tavily ile web araması yapar, Gemini Flash-Lite ile özetler.")
                }
                Section("İlaç uyarısı") {
                    Text("Bu uygulamadaki ilaç bilgileri doktor/eczacı tavsiyesi değildir. Prospektüs ve resmi kaynaklar kontrol edilmelidir.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Ayarlar")
        }
    }
}

struct HistoryView: View {
    var body: some View {
        PremiumScreen {
            VStack(spacing: 20) {
                RadarLogo()
                    .frame(width: 120, height: 120)
                Text("Geçmiş")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                Text("Sonraki sürümde aramalar cihazda saklanacak. Şimdilik sonuçları linklerden tekrar açabilirsiniz.")
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.muted)
                    .padding(.horizontal, 36)
                Spacer(minLength: 160)
            }
            .padding(.top, 120)
        }
    }
}

// MARK: - Visual Illustrations

struct RadarLogo: View {
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .trim(from: 0.06, to: 0.85)
                    .stroke(
                        LinearGradient(colors: [AppTheme.blue, AppTheme.cyan], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: CGFloat(7 - i), lineCap: .round)
                    )
                    .frame(width: CGFloat(96 - i * 24), height: CGFloat(96 - i * 24))
                    .rotationEffect(.degrees(Double(i) * 12 - 18))
            }
            Circle().fill(AppTheme.blue).frame(width: 12, height: 12)
            Capsule()
                .fill(LinearGradient(colors: [AppTheme.cyan, AppTheme.blue], startPoint: .leading, endPoint: .trailing))
                .frame(width: 62, height: 12)
                .rotationEffect(.degrees(-40))
                .offset(x: 19, y: -18)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.navy)
                .frame(width: 38, height: 38)
                .rotationEffect(.degrees(39))
                .offset(x: 42, y: 18)
                .overlay(Circle().fill(.white).frame(width: 7, height: 7).offset(x: 36, y: 8))
        }
    }
}

struct BarcodeTagIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white)
                .frame(width: 150, height: 190)
                .rotationEffect(.degrees(14))
                .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 9)
                .overlay(alignment: .top) {
                    Circle()
                        .stroke(AppTheme.navy.opacity(0.45), lineWidth: 4)
                        .frame(width: 22, height: 22)
                        .offset(y: 16)
                        .rotationEffect(.degrees(14))
                }
            HStack(spacing: 4) {
                ForEach(0..<11) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(AppTheme.navy)
                        .frame(width: index % 3 == 0 ? 5 : 3, height: CGFloat(72 + (index % 4) * 10))
                }
            }
            .rotationEffect(.degrees(14))
            .offset(y: 26)
            Text("868123 456789")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.navy.opacity(0.75))
                .rotationEffect(.degrees(14))
                .offset(y: 76)
        }
    }
}

struct CapsuleHeroIllustration: View {
    var body: some View {
        ZStack {
            Image(systemName: "shield")
                .font(.system(size: 96, weight: .thin))
                .foregroundColor(.white.opacity(0.20))
                .offset(x: -18, y: -34)
            Capsule()
                .fill(LinearGradient(colors: [.white, Color(red: 0.92, green: 0.98, blue: 0.97)], startPoint: .top, endPoint: .bottom))
                .frame(width: 76, height: 150)
                .rotationEffect(.degrees(47))
                .offset(x: -4, y: 8)
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 8)
            Capsule()
                .trim(from: 0, to: 0.50)
                .fill(LinearGradient(colors: [AppTheme.mint, AppTheme.emerald], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 76, height: 150)
                .rotationEffect(.degrees(47))
                .offset(x: -4, y: 8)
            Circle()
                .fill(.white.opacity(0.92))
                .frame(width: 88, height: 88)
                .offset(x: 76, y: 48)
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 8)
                .overlay(Rectangle().fill(AppTheme.muted.opacity(0.22)).frame(width: 72, height: 2).rotationEffect(.degrees(15)).offset(x: 76, y: 48))
        }
    }
}

struct KeyboardSearchIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(.white.opacity(0.18))
                .frame(width: 202, height: 58)
                .rotationEffect(.degrees(-8))
                .offset(x: 0, y: -54)
                .overlay {
                    HStack {
                        Text("İlaç adı yazın...")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.muted)
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.title3.bold())
                            .foregroundColor(AppTheme.navy)
                    }
                    .padding(.horizontal, 18)
                    .frame(width: 190, height: 48)
                    .background(.white.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .rotationEffect(.degrees(-8))
                    .offset(x: 0, y: -54)
                }
            VStack(spacing: 7) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 7) {
                        ForEach(0..<6) { _ in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(.white.opacity(0.78))
                                .frame(width: 26, height: 20)
                        }
                    }
                }
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.82)).frame(width: 88, height: 22)
                    Text("Ara")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .frame(width: 50, height: 22)
                        .background(AppTheme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(14)
            .background(.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .rotationEffect(.degrees(8))
            .offset(x: 18, y: 42)
        }
    }
}

struct MedicineScanIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white)
                .frame(width: 138, height: 96)
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paracetamol")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(AppTheme.navy)
                        Text("500 mg Tablet")
                            .font(.caption.bold())
                            .foregroundColor(AppTheme.emerald)
                        Spacer()
                        Text("20 Tablet")
                            .font(.caption2.bold())
                            .foregroundColor(AppTheme.muted)
                    }
                    .padding(12)
                }
            ForEach(0..<4) { index in
                CornerBracket()
                    .stroke(AppTheme.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 46, height: 46)
                    .rotationEffect(.degrees(Double(index) * 90))
                    .offset(x: index == 0 || index == 3 ? -86 : 86, y: index < 2 ? -66 : 66)
            }
            Circle()
                .fill(.white.opacity(0.95))
                .frame(width: 58, height: 58)
                .overlay(Image(systemName: "camera.fill").foregroundColor(AppTheme.emerald).font(.title3.bold()))
                .offset(x: 20, y: 83)
        }
    }
}

struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return p
    }
}

struct MedicineBoxIllustration: View {
    let name: String
    let form: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white)
                .frame(width: 190, height: 120)
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 10)
            Path { path in
                path.move(to: CGPoint(x: 10, y: 92))
                path.addCurve(to: CGPoint(x: 185, y: 63), control1: CGPoint(x: 65, y: 110), control2: CGPoint(x: 118, y: 34))
                path.addLine(to: CGPoint(x: 185, y: 120))
                path.addLine(to: CGPoint(x: 10, y: 120))
            }
            .fill(LinearGradient(colors: [AppTheme.blue.opacity(0.85), AppTheme.navy], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 190, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(name.uppercased())
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(form)
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Text("20 Film Tablet")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            .padding(14)
            .frame(width: 190, height: 120, alignment: .leading)
        }
    }
}

struct MedicineBoxMini: View {
    let name: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(name.prefix(10)))
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                    .lineLimit(1)
                Text("%0.2")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.blue)
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(AppTheme.blue).frame(height: 18)
            }
            .padding(9)
        }
    }
}

struct HeadphoneIllustration: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.92)).frame(width: 76, height: 76).offset(x: -42, y: 36)
            Circle().fill(Color.black.opacity(0.92)).frame(width: 76, height: 76).offset(x: 42, y: 36)
            Circle().fill(Color(red: 0.05, green: 0.06, blue: 0.07)).frame(width: 48, height: 48).offset(x: -42, y: 36)
            Circle().fill(Color(red: 0.05, green: 0.06, blue: 0.07)).frame(width: 48, height: 48).offset(x: 42, y: 36)
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.black.opacity(0.90), style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .frame(width: 150, height: 160)
                .offset(y: 20)
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.96)).frame(width: 34, height: 86).offset(x: -65, y: 21)
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.96)).frame(width: 34, height: 86).offset(x: 65, y: 21)
        }
        .rotationEffect(.degrees(-7))
    }
}

// MARK: - UIKit Picker / Helpers

struct ImagePicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

func openURL(_ value: String) {
    guard let url = URL(string: value), UIApplication.shared.canOpenURL(url) else { return }
    UIApplication.shared.open(url)
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
