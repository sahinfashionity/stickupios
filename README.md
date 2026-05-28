# EtiketRadar iOS - Yeni Premium Tasarım

Bu klasör Codemagic ile IPA üretmek için hazırdır.

## Ana dosya

```text
EtiketRadar/EtiketRadarApp.swift
```

## Yapı

- SwiftUI tek dosya uygulama
- Vision OCR cihaz içinde çalışır
- Backend URL ve APP_API_KEY Ayarlar ekranından girilir
- Tavily/Gemini API anahtarları iPhone içinde tutulmaz, sadece Vercel Environment Variables içindedir

## Yeni ekranlar

- Ana ekran: Etiket / İlaç büyük görsel kartları
- İlaç Asistanı: Manuel Ekle / Fotoğraf Çek
- İlaç Sonuçları: fiyat, kullanım talimatı, yan etkiler, doktor uyarısı
- Etiket Karşılaştır: marka/model/açıklama ve fiyat listesi
- Satın Al: tam ekran açılır, yüksekliği tüm ekranı kaplar

## Codemagic

Workflow:

```text
EtiketRadar iOS unsigned IPA
```
