//+------------------------------------------------------------------+
//| Analysts.mqh                                                       |
//|                                                                    |
//| Pembangun system prompt & data JSON per analis -- diadaptasi 1:1   |
//| dari src/analysts.js (baseHeader/pillarRoleNote/ANALYSTS array).   |
//| FASE 1 baru punya 2 analis (Trend, Momentum) buat tes end-to-end.  |
//| Analis lain NYUSUL di fase berikutnya dengan pola yang SAMA persis |
//| -- tinggal tambah 1 fungsi BuildXxxSystemPrompt() + 1 fungsi        |
//| BuildXxxDataJson() per analis baru.                                |
//|                                                                    |
//| CATATAN: Momentum di versi JS aslinya baca RSI+MACD+Stochastic;    |
//| Fase 1 ini SEMENTARA cuma pakai RSI14 (MACD/Stochastic nyusul di   |
//| MarketSnapshot fase berikutnya) -- supaya kerangka+state machine   |
//| bisa dites jalan dulu tanpa nunggu semua indikator lengkap.        |
//+------------------------------------------------------------------+
#property strict
#include "MarketSnapshot.mqh"

//+------------------------------------------------------------------+
//| Balikin catatan peran pilar -- SAMA PERSIS teksnya dengan          |
//| pillarRoleNote() di analysts.js, biar kualitas hasil AI konsisten  |
//| dengan versi Worker yang sudah terbukti bagus.                     |
//+------------------------------------------------------------------+
string PillarRoleNote(const string pillar)
  {
   if(pillar == "supporting")
      return "PERAN ANDA: Analis Pendukung dalam strategi \"Konfluensi 3 Pilar\". Opini Anda TIDAK menentukan arah sinyal utama — tugas Anda MENDUKUNG atau MEMBERI PERINGATAN terhadap 3 pilar utama (Trend, Level Kunci, Momentum). Jangan berperilaku seolah opini Anda setara bobotnya dengan AI pilar utama.";

   string pillarLabel = pillar; // "trend" / "momentum" / "level" -- label sudah cukup jelas apa adanya
   return "PERAN ANDA: pemegang pilar " + pillarLabel + ", salah satu dari 3 PILAR UTAMA strategi \"Konfluensi 3 Pilar\". Bias arah Anda IKUT MENENTUKAN keputusan akhir secara langsung — sistem akan mengecek apakah ke-3 pilar (Trend, Level Kunci, Momentum) SEARAH sebelum memutuskan sinyal kuat atau WAIT. Jangan ragu-ragu di baris \"Bias:\" — beri kesimpulan tegas berdasar data.";
  }

//+------------------------------------------------------------------+
//| Header dasar yang sama buat SEMUA analis -- SAMA PERSIS dengan     |
//| baseHeader() di analysts.js.                                      |
//+------------------------------------------------------------------+
string BaseHeader(const string title, const string symbol, const string tradeMode, const string pillar)
  {
   string s = "Anda adalah AI spesialis trading futures dengan peran: " + title + ".\n";
   s += PillarRoleNote(pillar) + "\n";
   s += "Simbol: " + symbol + ". Mode trading: " + tradeMode + ".\n";
   s += "Analisa HANYA dari data JSON yang diberikan (jangan menebak di luar data itu).\n";
   s += "Beri opini SINGKAT (maksimal 5 kalimat): kesimpulan dari sudut pandang Anda, dan bias arah (Bullish/Bearish/Netral).\n";
   s += "Bahasa Indonesia, langsung ke inti, tanpa basa-basi.\n";
   s += "WAJIB akhiri jawaban Anda dengan baris baru PERSIS berformat: \"Bias: Bullish\" atau \"Bias: Bearish\" atau \"Bias: Netral\" (pilih satu, tanpa tambahan kata lain di baris itu — ini dipakai sistem untuk menghitung tally & keselarasan pilar otomatis).";
   return s;
  }

//+------------------------------------------------------------------+
//| ANALIS #1 -- Spesialis Trend (Moving Averages). Pilar UTAMA.       |
//+------------------------------------------------------------------+
string BuildTrendSystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Trend (Moving Averages)", symbol, tradeMode, "trend");
   s += "\nTugas: tentukan apakah pasar Uptrend, Downtrend, atau Choppy/Sideways berdasarkan posisi harga relatif terhadap EMA20, EMA50, EMA200. Sebagai PILAR 1, kesimpulan Anda jadi acuan ARAH BESAR yang harus didukung 2 pilar lain (Level Kunci & Momentum) sebelum sinyal dianggap kuat.";
   return s;
  }

string BuildTrendDataJson(const MarketSnapshot &snap)
  {
   return StringFormat("{\"lastPrice\":%.2f,\"ema20\":%.2f,\"ema50\":%.2f,\"ema200\":%.2f}",
                        snap.lastPrice, snap.ema20, snap.ema50, snap.ema200);
  }

//+------------------------------------------------------------------+
//| ANALIS #2 -- Spesialis Momentum (Oscillators). Pilar UTAMA.        |
//| (Fase 1: cuma RSI14 -- MACD & Stochastic nyusul)                   |
//+------------------------------------------------------------------+
string BuildMomentumSystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Momentum (Oscillators)", symbol, tradeMode, "momentum");
   s += "\nTugas: baca RSI. Nilai apakah pergerakan harga didukung momentum kuat, atau ada indikasi Divergence (sinyal pembalikan). Sebagai bagian PILAR 3 (Momentum/Konfirmasi), fokus jawab: apakah momentum saat ini MENGKONFIRMASI entry ke arah tertentu SEKARANG, bukan cuma arah umum jangka panjang.\n";
   s += "CATATAN FASE PENGEMBANGAN: data MACD & Stochastic BELUM tersedia di versi ini (nyusul) -- analisa HANYA dari RSI14 dulu.";
   return s;
  }

string BuildMomentumDataJson(const MarketSnapshot &snap)
  {
   return StringFormat("{\"rsi14\":%.2f}", snap.rsi14);
  }

//+------------------------------------------------------------------+
//| Cari baris "Bias: Bullish/Bearish/Netral" di jawaban AI -- dipakai |
//| nanti (fase Penyimpul/tally) buat hitung keselarasan pilar. Fase 1 |
//| ini baru extract-nya doang, belum dipakai buat logic apa pun.      |
//+------------------------------------------------------------------+
string ExtractBiasFromOpinion(const string opinionText)
  {
   int pos = StringFind(opinionText, "Bias:");
   if(pos < 0)
      return "Netral"; // fallback aman kalau AI lupa format
   string tail = StringSubstr(opinionText, pos + StringLen("Bias:"));
   StringTrimLeft(tail);
   StringTrimRight(tail);
   // Ambil kata pertama aja (Bullish/Bearish/Netral), buang sisa baris
   // kalau ada karakter nyasar setelahnya.
   int lineEnd = StringFind(tail, "\n");
   if(lineEnd >= 0)
      tail = StringSubstr(tail, 0, lineEnd);
   StringTrimRight(tail);
   return tail;
  }
//+------------------------------------------------------------------+
