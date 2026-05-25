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

enum SearchMode: String {
    case medicine
    case label
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
        request.timeoutInterval = 75
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

// MARK: - Root / Settings

struct RootView: View {
    @AppStorage("backendBaseURL") private var backendBaseURL = "https://etiket-radar-backend.vercel.app/"
    @AppStorage("appApiKey") private var appApiKey = "etiket-radar-123456"

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(client: client)
            }
            .tabItem { Label("Ana Sayfa", systemImage: "house.fill") }

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("Geçmiş", systemImage: "clock") }

            NavigationStack {
                SettingsView(backendBaseURL: $backendBaseURL, appApiKey: $appApiKey)
            }
            .tabItem { Label("Ayarlar", systemImage: "gearshape.fill") }
        }
        .accentColor(AppTheme.blue)
    }

    private var client: APIClient { APIClient(baseURL: backendBaseURL, apiKey: appApiKey) }
}

struct HomeView: View {
    let client: APIClient

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 26) {
                AppHeader(title: "EtiketRadar", subtitle: "Akıllı fiyat ve ürün asistanı", icon: "tag.circle.fill", showBack: false)
                    .padding(.top, 8)

                Spacer(minLength: 10)

                NavigationLink {
                    LabelLandingView(client: client)
                } label: {
                    BigActionCard(
                        title: "Etiket",
                        subtitle: "Fiyatları tara, anında karşılaştır.",
                        icon: "tag.fill",
                        tint: AppTheme.blue,
                        background: AppTheme.blue.opacity(0.10)
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    MedicineLandingView(client: client)
                } label: {
                    BigActionCard(
                        title: "İlaç",
                        subtitle: "Fiyat, prospektüs ve yan etki bilgisi.",
                        icon: "pills.fill",
                        tint: AppTheme.green,
                        background: AppTheme.green.opacity(0.12)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                InfoStrip(text: "EtiketRadar; görselden OCR ile metin algılar, Tavily ile web araması yapar, ucuz LLM ile kaynakları özetler.")
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 22)
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
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                AppHeader(title: "İlaç Asistanı", subtitle: "İlaç bilgilerini hızlıca öğren", icon: "pills.fill", showBack: true) { dismiss() }
                    .padding(.top, 8)

                Spacer(minLength: 20)

                Button { showManual = true } label: {
                    BigActionCard(title: "Manuel Ekle", subtitle: "İlacın adını yazarak ara", icon: "keyboard.fill", tint: AppTheme.green, background: AppTheme.green.opacity(0.12))
                }
                .buttonStyle(.plain)

                Button { showCamera = true } label: {
                    BigActionCard(title: "Resim Çek", subtitle: "Kutunun fotoğrafını çek, OCR algılasın", icon: "camera.fill", tint: AppTheme.blue, background: AppTheme.blue.opacity(0.10))
                }
                .buttonStyle(.plain)

                InfoStrip(text: "Fiyat, kullanım talimatı ve yan etkiler kaynaklara göre özetlenir. Doktor tavsiyesi değildir.")

                Spacer()
            }
            .padding(.horizontal, 22)

            if let loadingMessage { LoadingOverlay(message: loadingMessage) }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showManual) {
            ManualSearchSheet(title: "İlaç adı yaz", placeholder: "Örn: Majezik 100 mg veya Ofnol S %0.2") { query in
                showManual = false
                Task { await searchMedicine(query: query, ocrText: nil) }
            }
            .presentationDetents([.height(300)])
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
            let query = bestQuery(from: text)
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

    private func bestQuery(from text: String) -> String {
        let lines = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let useful = lines.first { line in
            let upper = line.uppercased()
            return upper.count >= 4 && !upper.contains("KULLAN") && !upper.contains("SAKL") && !upper.contains("BARKOD")
        }
        return useful ?? text.replacingOccurrences(of: "\n", with: " ")
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
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                AppHeader(title: "Etiket Karşılaştır", subtitle: "Mağaza fiyatını internette kontrol et", icon: "tag.fill", showBack: true) { dismiss() }
                    .padding(.top, 8)

                Spacer(minLength: 20)

                Button { showCamera = true } label: {
                    BigActionCard(title: "Etiket Fotoğrafı", subtitle: "Raf etiketi veya ürün kutusunu çek", icon: "camera.viewfinder", tint: AppTheme.blue, background: AppTheme.blue.opacity(0.10))
                }
                .buttonStyle(.plain)

                Button { showManual = true } label: {
                    BigActionCard(title: "Manuel Ürün Ara", subtitle: "Marka, model veya barkod yaz", icon: "magnifyingglass", tint: AppTheme.green, background: AppTheme.green.opacity(0.12))
                }
                .buttonStyle(.plain)

                InfoStrip(text: "Elektronik, market, kozmetik ve mağaza ürünlerinde internet fiyatlarını karşılaştırır; en ucuz satıcıyı öne çıkarır.")

                Spacer()
            }
            .padding(.horizontal, 22)

            if let loadingMessage { LoadingOverlay(message: loadingMessage) }
        }
        .navigationBarHidden(true)
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
            let query = text.replacingOccurrences(of: "\n", with: " ")
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
}

// MARK: - Result Views

struct MedicineResultView: View {
    let response: MedicineResponse
    @State private var selectedOffer: ProductOffer?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppHeader(title: "İlaç Sonuçları", subtitle: response.query, icon: "pills.fill", showBack: true)

                    ResultHeroCard(
                        title: response.medicine?.name ?? response.query,
                        subtitle: [response.medicine?.activeIngredient, response.medicine?.form, response.medicine?.packageInfo].compactMap { $0 }.joined(separator: " • "),
                        icon: "pills.fill",
                        tint: AppTheme.green
                    )

                    OfferSection(title: "İnternet Fiyatları", offers: response.offers) { offer in selectedOffer = offer }

                    TextSection(title: "Kullanım Talimatı", icon: "doc.text.fill", items: response.usageInstructions)
                    TextSection(title: "Yan Etkiler", icon: "exclamationmark.triangle.fill", items: response.sideEffects)
                    TextSection(title: "Önemli Uyarılar", icon: "shield.lefthalf.filled", items: response.warnings + [response.disclaimer ?? "Bu bilgiler kaynak özetidir; doktor/eczacı tavsiyesi yerine geçmez."])

                    SourcesSection(sources: response.sources)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            if let selectedOffer {
                OfferPopup(offer: selectedOffer) { self.selectedOffer = nil }
            }
        }
        .navigationBarHidden(true)
    }
}

struct LabelResultView: View {
    let response: LabelResponse
    @State private var selectedOffer: ProductOffer?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppHeader(title: "Etiket Karşılaştır", subtitle: "AI + Tavily fiyat karşılaştırma", icon: "tag.fill", showBack: true)

                    ResultHeroCard(
                        title: response.product?.productName ?? response.query,
                        subtitle: [response.product?.brand, response.product?.model, response.product?.description].compactMap { $0 }.joined(separator: " • "),
                        icon: "tag.fill",
                        tint: AppTheme.blue
                    )

                    if let best = response.offers.first {
                        BestPriceCard(offer: best) { selectedOffer = best }
                    }

                    OfferSection(title: "Fiyat Karşılaştırması", offers: response.offers) { offer in selectedOffer = offer }
                    TextSection(title: "Alışveriş Tavsiyeleri", icon: "lightbulb.fill", items: response.suggestions)
                    SourcesSection(sources: response.sources)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            if let selectedOffer { OfferPopup(offer: selectedOffer) { self.selectedOffer = nil } }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Reusable UI

struct AppTheme {
    static let blue = Color(red: 0.05, green: 0.38, blue: 0.95)
    static let green = Color(red: 0.05, green: 0.65, blue: 0.42)
    static let navy = Color(red: 0.04, green: 0.08, blue: 0.25)
    static let muted = Color(red: 0.37, green: 0.43, blue: 0.55)
    static let card = Color.white.opacity(0.92)
    static let background = LinearGradient(colors: [Color.white, Color(red: 0.95, green: 0.98, blue: 1.0)], startPoint: .top, endPoint: .bottom)
}

struct AppHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String
    let icon: String
    var showBack: Bool
    var customBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            if showBack {
                Button { if let customBack { customBack() } else { dismiss() } } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundColor(AppTheme.navy)
                        .frame(width: 48, height: 48)
                        .background(.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
                }
            }
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(showBack ? AppTheme.green : AppTheme.blue)
                .frame(width: 58, height: 58)
                .background((showBack ? AppTheme.green : AppTheme.blue).opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppTheme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "bell")
                .font(.title3.weight(.semibold))
                .foregroundColor(AppTheme.muted)
                .frame(width: 46, height: 46)
                .background(.white)
                .clipShape(Circle())
                .overlay(alignment: .topTrailing) { Circle().fill(AppTheme.blue).frame(width: 9, height: 9).padding(8) }
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        }
    }
}

struct BigActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let background: Color

    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: icon)
                .font(.system(size: 52, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 104, height: 104)
                .background(Circle().fill(.white.opacity(0.75)))
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                Text(subtitle)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppTheme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.title.bold())
                .foregroundColor(tint)
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.90))
                .clipShape(Circle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 176)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(tint.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: tint.opacity(0.10), radius: 18, x: 0, y: 12)
    }
}

struct InfoStrip: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill").foregroundColor(AppTheme.blue).font(.title2)
            Text(text).font(.callout.weight(.medium)).foregroundColor(AppTheme.muted)
            Spacer()
        }
        .padding(16)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.blue.opacity(0.12), lineWidth: 1))
    }
}

struct ManualSearchSheet: View {
    let title: String
    let placeholder: String
    let onSearch: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.title2.bold()).foregroundColor(AppTheme.navy)
                Spacer()
                Button("Kapat") { dismiss() }
            }
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Button { onSearch(text) } label: {
                Text("Ara")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(AppTheme.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(24)
    }
}

struct ResultHeroCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 92, height: 92)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 22))
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.navy)
                Label("AI ile özetlendi", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundColor(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
                if !subtitle.isEmpty {
                    Text(subtitle).font(.callout).foregroundColor(AppTheme.muted)
                }
            }
            Spacer()
        }
        .padding(18)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

struct OfferSection: View {
    let title: String
    let offers: [ProductOffer]
    let onTap: (ProductOffer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "tag.fill")
                    .font(.title3.bold())
                    .foregroundColor(AppTheme.navy)
                Spacer()
                Text("\(offers.count) sonuç")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.muted)
            }
            if offers.isEmpty {
                Text("Sonuç bulunamadı. Daha net marka/model veya doz bilgisiyle tekrar deneyin.")
                    .font(.callout)
                    .foregroundColor(AppTheme.muted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(offers) { offer in
                    Button { onTap(offer) } label: {
                        HStack(spacing: 12) {
                            Circle().fill(AppTheme.blue.opacity(0.10)).frame(width: 44, height: 44)
                                .overlay(Text(String(offer.siteName.prefix(1))).font(.headline.bold()).foregroundColor(AppTheme.blue))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(offer.siteName).font(.headline).foregroundColor(AppTheme.navy)
                                Text(offer.note ?? offer.title).font(.caption).foregroundColor(AppTheme.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(offer.priceText.isEmpty ? "Link" : offer.priceText)
                                .font(.headline.bold())
                                .foregroundColor(offer.priceText.isEmpty ? AppTheme.blue : AppTheme.green)
                            Image(systemName: "chevron.right").foregroundColor(AppTheme.blue)
                        }
                        .padding(14)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct BestPriceCard: View {
    let offer: ProductOffer
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundColor(AppTheme.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("En Uygun Fiyat").font(.caption.bold()).foregroundColor(AppTheme.green)
                Text(offer.priceText.isEmpty ? offer.siteName : offer.priceText)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.green)
            }
            Spacer()
            Button(action: action) {
                Label("Siteye Git", systemImage: "arrow.up.right.square")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AppTheme.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(AppTheme.green.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.green.opacity(0.25), lineWidth: 1))
    }
}

struct TextSection: View {
    let title: String
    let icon: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.title3.bold()).foregroundColor(AppTheme.navy)
            if items.isEmpty {
                Text("Bu bölüm için güvenilir kaynaklardan yeterli bilgi alınamadı.").foregroundColor(AppTheme.muted)
            } else {
                ForEach(items.prefix(6), id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").font(.headline).foregroundColor(AppTheme.blue)
                        Text(item).font(.callout).foregroundColor(AppTheme.muted)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

struct SourcesSection: View {
    let sources: [SourceLink]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Kaynaklar", systemImage: "link").font(.title3.bold()).foregroundColor(AppTheme.navy)
            ForEach(sources.prefix(6)) { source in
                Button { openURL(source.url) } label: {
                    HStack {
                        Text(source.title).font(.callout.weight(.medium)).lineLimit(1).foregroundColor(AppTheme.blue)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

struct OfferPopup: View {
    let offer: ProductOffer
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 18) {
                HStack {
                    Image(systemName: "bag.fill")
                        .font(.title)
                        .foregroundColor(AppTheme.blue)
                        .frame(width: 56, height: 56)
                        .background(AppTheme.blue.opacity(0.12))
                        .clipShape(Circle())
                    Text("Satın Al")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.navy)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.title3.bold())
                            .foregroundColor(AppTheme.muted)
                            .frame(width: 44, height: 44)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(offer.title).font(.title3.bold()).foregroundColor(AppTheme.navy)
                    HStack {
                        Text(offer.siteName).font(.headline).foregroundColor(AppTheme.blue)
                        Spacer()
                        Text(offer.priceText.isEmpty ? "Fiyat sayfada" : offer.priceText).font(.title3.bold()).foregroundColor(AppTheme.green)
                    }
                    if let note = offer.note, !note.isEmpty {
                        Text(note).font(.callout).foregroundColor(AppTheme.muted)
                    }
                    Text(offer.url).font(.caption).foregroundColor(AppTheme.muted).lineLimit(2)
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Button { openURL(offer.url) } label: {
                    Label("Siteye Git", systemImage: "arrow.up.right.square")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(AppTheme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                Button("Kapat", action: close)
                    .font(.headline.bold())
                    .foregroundColor(AppTheme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding(22)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.20), radius: 26, x: 0, y: 18)
            .padding(.horizontal, 28)
        }
    }
}

struct LoadingOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.20).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.3)
                Text(message).font(.headline).foregroundColor(AppTheme.navy)
            }
            .padding(24)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(radius: 20)
        }
    }
}

struct SettingsView: View {
    @Binding var backendBaseURL: String
    @Binding var appApiKey: String

    var body: some View {
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
            Section("Uyarı") {
                Text("İlaç bilgileri doktor/eczacı tavsiyesi değildir. Prospektüs ve resmi kaynaklar kontrol edilmelidir.")
            }
        }
        .navigationTitle("Ayarlar")
    }
}

struct HistoryView: View {
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 50)).foregroundColor(AppTheme.blue)
                Text("Geçmiş").font(.largeTitle.bold()).foregroundColor(AppTheme.navy)
                Text("Sonraki sürümde aramalar cihazda saklanacak. Şimdilik sonuçları linklerden tekrar açabilirsiniz.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.muted)
                    .padding(.horizontal, 28)
            }
        }
    }
}

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
