# EtiketRadar iOS - Tavily + Gemini Backend Uyumlu

Bu sürümde uygulama açıldığında iki büyük seçenek görünür:

- Etiket
- İlaç

## İlaç akışı

- Manuel Ekle: tek satırlık ilaç adı girilir.
- Resim Çek: ilaç kutusu fotoğrafından Apple Vision OCR ile metin çıkarılır.
- Backend Tavily ile arama yapar, Gemini Flash-Lite ile özetler.
- Sonuç ekranında fiyatlar, kullanım talimatı, yan etkiler ve kaynaklar görünür.
- Satın Al pop-up içinde fiyat, site adı ve tıklanabilir link gösterilir.

## Etiket akışı

- Mağaza/market/elektronik ürün etiketi fotoğrafı çekilir veya manuel ürün adı yazılır.
- OCR ile marka/model/açıklama çıkarılmaya çalışılır.
- Tavily ile Türkiye alışveriş sitelerinde fiyatlar aranır.
- En uygun fiyat ve satıcı listesi gösterilir.

## Codemagic

Repo kökünde `codemagic.yaml` ve `project.yml` vardır.
Codemagic workflow: `EtiketRadar iOS unsigned IPA`

## Backend ayarları

Uygulama > Ayarlar:

```text
Backend URL: https://etiket-radar-backend.vercel.app/
Uygulama API anahtarı: etiket-radar-123456
```
