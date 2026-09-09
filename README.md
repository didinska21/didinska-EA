# DidinskaSignalEA

EA (Expert Advisor) MetaTrader 5 yang mem-port strategi **"Konfluensi 3 Pilar"** dari Didinska Signal Bot (Cloudflare Workers) ke MQL5 native. Setiap siklus, EA memanggil **10 AI analis spesialis + 1 AI Penyimpul** (total 11 pemanggilan AI) untuk menghasilkan 1 sinyal trading, lalu mengirim hasilnya ke Telegram.

> **Fase 2** — fokus ke kualitas analisa & sinyal. **Belum ada** eksekusi order otomatis, logging riwayat sinyal lokal, atau guardrail risiko harian. Menyusul di fase berikutnya setelah sinyal teksnya terbukti stabil.

---

## Struktur File

| File | Fungsi |
|---|---|
| `DidinskaSignalEA.mq5` | File utama — state machine, routing 10 analis, input EA |
| `Analysts.mqh` | System prompt & data JSON untuk masing-masing 10 analis |
| `Summarizer.mqh` | System prompt AI Penyimpul + helper tally bias/pilar |
| `MarketSnapshot.mqh` | Ambil data pasar native lewat indicator handle MQL5 |
| `OpenAiCompatibleApi.mqh` | Wrapper panggilan AI untuk provider format OpenAI (Groq, OpenRouter, dll) |
| `AnthropicApi.mqh` | Wrapper panggilan AI khusus Anthropic |
| `TelegramApi.mqh` | Kirim/edit pesan Telegram |
| `JsonHelper.mqh` | Helper parsing JSON sederhana |

---

## Setup Sebelum Dijalankan

1. **Compile** di MetaEditor (F7). Kalau ada error compile, kirim pesan errornya persis untuk diperbaiki.
2. **Tools > Options > Expert Advisors** → centang **"Allow WebRequest for listed URL"**, tambahkan PERSIS:
   - `https://api.groq.com` (default — provider AI live)
   - `https://api.telegram.org` (notifikasi)
   - `https://api.anthropic.com` (HANYA kalau `Inp_UseAnthropic=true`)
3. Isi input API key — pilih **salah satu** dari dua opsi:
   - **Opsi A (simpel):** isi `Inp_OpenAiApiKey` (1 key fallback bersama), biarkan 11 slot `Inp_ApiKey_1..10` + `Inp_ApiKey_Summarizer` kosong.
   - **Opsi B (hindari rate limit):** isi semua 11 slot (`Inp_ApiKey_1` s/d `Inp_ApiKey_10` + `Inp_ApiKey_Summarizer`) dengan key/akun Groq yang berbeda-beda. Kalau semua 11 slot sudah lengkap, `Inp_OpenAiApiKey` (fallback) **boleh dikosongkan**.
4. Isi `Inp_TelegramBotToken` dan `Inp_TelegramChatId` untuk notifikasi.
5. Attach EA ke chart simbol yang diinginkan (contoh: XAUUSD, M15), centang **"Allow Algo Trading"** (tombol di toolbar juga harus aktif/hijau).

---

## Penjelasan Input Penting

| Input | Keterangan |
|---|---|
| `Inp_UseAnthropic` | `false` = pakai Groq/provider format OpenAI (default). `true` = pakai Anthropic (berbayar). |
| `Inp_OpenAiBaseUrl` | Endpoint chat-completions provider. **Wajib diisi** kalau `Inp_UseAnthropic=false`. Contoh Groq: `https://api.groq.com/openai/v1/chat/completions` |
| `Inp_OpenAiApiKey` | Key fallback bersama. Wajib diisi **kecuali** semua 11 slot `Inp_ApiKey_1..10` + `Inp_ApiKey_Summarizer` sudah terisi. |
| `Inp_ApiKey_1` s/d `Inp_ApiKey_10` | Key khusus per-analis (opsional). Kosong = pakai fallback. |
| `Inp_ApiKey_Summarizer` | Key khusus AI Penyimpul / AI ke-11 (opsional). Kosong = pakai fallback. |
| `Inp_OpenAiModel` | Model untuk 10 analis. |
| `Inp_OpenAiSummaryModel` | Model untuk AI Penyimpul (boleh beda dari analis). |
| `Inp_MaxTokensAnalyst` / `Inp_MaxTokensSummarizer` | Batas token jawaban tiap panggilan AI. |
| `Inp_CycleIntervalSec` | Jeda antar siklus penuh (detik). Default 600 = 10 menit. |
| `Inp_StepIntervalSec` | Jeda antar langkah state machine (detik). Default 3 detik — jangan diisi 0. |
| `Inp_WebRequestTimeoutMs` | Timeout tiap panggilan API. |

---

## Alur Kerja (State Machine)

```
STATE_GATHER_DATA
      ↓
STATE_CALL_ANALYST   (diulang 10x, 1 analis per langkah)
      ↓
STATE_CALL_SUMMARIZER
      ↓
STATE_REPORT          → kirim/edit pesan Telegram hasil final
      ↓
STATE_WAIT_NEXT_CYCLE → tunggu Inp_CycleIntervalSec, ulang dari atas
```

Progres tiap analis di-update secara live ke 1 pesan Telegram yang sama (edit pesan), bukan kirim pesan baru tiap langkah.

---

## Riwayat Perbaikan Bug

### v2.01 (2026-09-09)
- **Fix validasi `OnInit()`:** sebelumnya `Inp_OpenAiApiKey` (fallback) selalu wajib diisi meskipun semua 11 slot key individual sudah lengkap — EA menolak jalan (`INIT_PARAMETERS_INCORRECT`) walau sebenarnya tidak butuh fallback sama sekali. Sekarang fallback hanya wajib kalau ada slot yang masih kosong.

### `OpenAiCompatibleApi.mqh` (2026-09-09)
- **Fix bug kritis:** `ArrayResize(postData, bodyLen - 1)` yang lama **selalu memotong byte terakhir** dari body JSON (karakter `}` penutup), karena `StringToCharArray` dipanggil dengan parameter `count` eksplisit sehingga TIDAK menambahkan null-terminator — trimming itu ternyata memotong data asli, bukan byte kosong. Ini menyebabkan **semua** panggilan AI (10 analis + Penyimpul) gagal dengan error provider `"failed to unmarshal JSON: unexpected end of JSON input"`. Baris trimming tersebut sudah dihapus.
- **Fix `OpenAiJsonEscape`:** ditambah penanganan surrogate pair UTF-16 (emoji dan karakter di luar BMP) supaya tidak terpotong saat escape per-karakter, plus escape control character `< 0x20` selain `\n \r \t` menjadi `\u00XX` sesuai spesifikasi JSON.

---

## Troubleshooting Cepat

| Gejala di Journal/Experts | Kemungkinan Penyebab |
|---|---|
| `expert removed` lalu `connection lost` | Masalah jaringan sesaat, biasanya auto-reconnect. Cek posisi tetap 0 sebelum re-attach. |
| `[Init] ... Inp_OpenAiApiKey (fallback)/Inp_OpenAiBaseUrl kosong` | Base URL kosong, atau fallback kosong padahal masih ada slot individual yang belum terisi (lihat v2.01 di atas). |
| `[AI n] GAGAL: Provider balas HTTP 400: unexpected end of JSON input` | Bug trimming body JSON — pastikan pakai `OpenAiCompatibleApi.mqh` versi terbaru (lihat changelog di atas). |
| `WebRequest gagal (error 4060)` | URL endpoint belum di-whitelist di Tools > Options > Expert Advisors. |
| `[Telegram] Gagal edit pesan (HTTP 1001)` | Biasanya sementara/tidak fatal — cek token & chat ID Telegram kalau berulang terus. |

---

## Rencana Fase Berikutnya

- Eksekusi order otomatis ke MT5 berdasarkan keputusan AI Penyimpul
- Logging riwayat sinyal secara lokal
- Guardrail risiko harian / maksimum jumlah trade per hari
