//+------------------------------------------------------------------+
//| Summarizer.mqh                                                     |
//|                                                                    |
//| FASE 2 -- AI Penyimpul (AI ke-11), diadaptasi dari                 |
//| src/groqVision.js (summarizeSignals + buildPillarWeightNote) dan   |
//| src/session_do.js (tallyBias, computePillarAlignment,              |
//| detectDecision, extractPriceAfterLabel, buildSignalCodeBlock).     |
//|                                                                    |
//| PENYEDERHANAAN vs versi JS (didokumentasikan biar jelas, bukan     |
//| disembunyikan):                                                    |
//| - enforceBiasTally() versi JS mem-parse & mengganti baris          |
//|   "Probabilitas" yang mungkin dobel/ber-markdown. Versi ini        |
//|   CUKUP menambahkan baris tally terpisah di akhir pesan -- lebih   |
//|   sederhana, informasinya tetap sama, cuma tidak "menyuntik" ke    |
//|   tengah teks AI.                                                  |
//| - extractPriceAfterLabel() versi JS pakai regex kompleks (dash     |
//|   variants, boundary lookahead). Versi ini pakai pemindaian        |
//|   karakter manual (MQL5 tidak punya regex bawaan) dengan pemilihan |
//|   kandidat angka TERDEKAT ke lastPrice, prinsipnya SAMA.           |
//+------------------------------------------------------------------+
#property strict
#include "Analysts.mqh"

//+------------------------------------------------------------------+
//| Escape teks AI biar aman ditaruh di pesan Telegram parse_mode HTML |
//| (cuma & < > yang wajib, sama seperti escapeHtml() di htmlUtil.js). |
//+------------------------------------------------------------------+
string EscapeHtml(const string src)
  {
   string out = src;
   StringReplace(out, "&", "&amp;");
   StringReplace(out, "<", "&lt;");
   StringReplace(out, ">", "&gt;");
   return out;
  }

//+------------------------------------------------------------------+
//| Cari index TERAKHIR dari sebuah substring (MQL5 StringFind cuma    |
//| cari dari kiri, jadi perlu loop manual).                           |
//+------------------------------------------------------------------+
int StringFindLast(const string text, const string needle)
  {
   int last = -1, from = 0;
   while(true)
     {
      int pos = StringFind(text, needle, from);
      if(pos < 0) break;
      last = pos;
      from = pos + 1;
     }
   return last;
  }

//+------------------------------------------------------------------+
//| Cari substring case-insensitive, balikin index di teks ASLI.       |
//+------------------------------------------------------------------+
int StringFindCI(const string text, const string needle, const int start = 0)
  {
   string t = text; StringToLower(t);
   string n = needle; StringToLower(n);
   return StringFind(t, n, start);
  }

//+------------------------------------------------------------------+
//| Tally bias dari 10 opini analis. biases[] harus sudah diisi        |
//| "Bullish"/"Bearish"/"Netral" (lewat ExtractBiasFromOpinion).       |
//+------------------------------------------------------------------+
void TallyBias(const string &biases[], int count, int &bullish, int &bearish, int &netral)
  {
   bullish = 0; bearish = 0; netral = 0;
   for(int i = 0; i < count; i++)
     {
      if(biases[i] == "Bullish") bullish++;
      else if(biases[i] == "Bearish") bearish++;
      else netral++;
     }
  }

//+------------------------------------------------------------------+
//| Bias mayoritas dari sekelompok nomor AI (anggota 1 pilar). Kalau   |
//| seri -> "Netral" (belum jelas), SAMA seperti pillarBias() di JS.   |
//+------------------------------------------------------------------+
string PillarBiasFromNumbers(const int &numbers[], const string &biasesByNumber[])
  {
   int bullish = 0, bearish = 0;
   for(int i = 0; i < ArraySize(numbers); i++)
     {
      string b = biasesByNumber[numbers[i] - 1]; // biasesByNumber index0 = AI#1
      if(b == "Bullish") bullish++;
      else if(b == "Bearish") bearish++;
     }
   if(bullish > bearish) return "Bullish";
   if(bearish > bullish) return "Bearish";
   return "Netral";
  }

//+------------------------------------------------------------------+
//| Hitung keselarasan strategi "Konfluensi 3 Pilar" -- SAMA logikanya |
//| dengan computePillarAlignment() di session_do.js, PILLAR_MAP mode  |
//| "lengkap": trend=[1], level=[5,6], momentum=[2,7].                 |
//+------------------------------------------------------------------+
void ComputePillarAlignment(const string &biasesByNumber[], string &trendBias, string &levelBias,
                             string &momentumBias, int &alignedCount, string &dominant)
  {
   int trendNums[1]    = {1};
   int levelNums[2]    = {5, 6};
   int momentumNums[2] = {2, 7};

   trendBias    = PillarBiasFromNumbers(trendNums, biasesByNumber);
   levelBias    = PillarBiasFromNumbers(levelNums, biasesByNumber);
   momentumBias = PillarBiasFromNumbers(momentumNums, biasesByNumber);

   int bullishCount = 0, bearishCount = 0;
   if(trendBias == "Bullish") bullishCount++; else if(trendBias == "Bearish") bearishCount++;
   if(levelBias == "Bullish") bullishCount++; else if(levelBias == "Bearish") bearishCount++;
   if(momentumBias == "Bullish") bullishCount++; else if(momentumBias == "Bearish") bearishCount++;

   if(bullishCount > bearishCount)      { dominant = "Bullish"; alignedCount = bullishCount; }
   else if(bearishCount > bullishCount) { dominant = "Bearish"; alignedCount = bearishCount; }
   else                                 { dominant = "Netral";  alignedCount = 0; }
  }

//+------------------------------------------------------------------+
//| Catatan strategi "Konfluensi 3 Pilar" -- SAMA PERSIS semangatnya   |
//| dengan buildPillarWeightNote() di groqVision.js.                   |
//+------------------------------------------------------------------+
string BuildPillarWeightNote(const int alignedCount, const string dominant,
                              const string trendBias, const string levelBias, const string momentumBias)
  {
   string pillarLines = "- Trend (Pilar 1): " + trendBias + "\n";
   pillarLines += "- Level Kunci (Pilar 2): " + levelBias + "\n";
   pillarLines += "- Momentum (Pilar 3): " + momentumBias;

   string instruction;
   if(alignedCount >= 3)
     {
      string arah = (dominant == "Bullish") ? "BUY" : (dominant == "Bearish") ? "SELL" : "sesuai arah mayoritas";
      instruction = "Ke-3 pilar SEARAH (" + dominant + ") — ini sinyal KUAT. Keputusan Anda SEBAIKNYA " + arah +
                    " (kecuali ada alasan kuat dari AI penunjang untuk menahan), dan Probabilitas boleh di kisaran LEBIH TINGGI (≈65-80%).";
     }
   else if(alignedCount == 2)
     {
      instruction = "Cuma 2 dari 3 pilar SEARAH (kecenderungan " + dominant + ") — sinyal BOLEH tetap dikeluarkan (BUY/SELL), TAPI WAJIB cantumkan 1 kalimat PERINGATAN RISIKO eksplisit yang menyebut pilar mana yang belum sejalan, dan Probabilitas WAJIB moderat saja (≈45-60%, JANGAN di atas 60%).";
     }
   else
     {
      instruction = "Pilar TIDAK cukup selaras (cuma " + IntegerToString(alignedCount) + " dari 3 pilar searah, atau tidak ada dominasi arah yang jelas) — dalam kondisi ini Keputusan WAJIB \"WAIT\", KECUALI Anda punya alasan sangat kuat & eksplisit dari data lain untuk tetap entry (harus dijelaskan alasannya, dan Probabilitas WAJIB rendah, ≤40%).";
     }

   string s = "\n\nCATATAN STRATEGI \"KONFLUENSI 3 PILAR\" — DIHITUNG OTOMATIS OLEH SISTEM (bukan tugas Anda menghitung ulang):\n";
   s += pillarLines + "\n";
   s += "Jumlah pilar yang searah: " + IntegerToString(alignedCount) + "/3.\n";
   s += instruction + "\n";
   s += "Sebutkan status keselarasan 3 pilar ini secara singkat di bagian 📊 Bias Arah atau 📍 Level Kunci (misal: \"3 pilar searah Bullish\" / \"2 dari 3 pilar searah, Momentum belum konfirmasi\").";
   return s;
  }

//+------------------------------------------------------------------+
//| System prompt AI Penyimpul -- diadaptasi dari summarizeSignals()   |
//| di groqVision.js (khusus mode 10-analis "lengkap", MQL5 tidak      |
//| punya mode "cepat"/"fiboqm").                                      |
//+------------------------------------------------------------------+
string BuildSummarizerSystemPrompt(const int opinionCount, const string symbol, const string tradeMode,
                                    const int bullish, const int bearish, const int netral,
                                    const int alignedCount, const string dominant,
                                    const string trendBias, const string levelBias, const string momentumBias)
  {
   string tallyLine = StringFormat("%d Bullish, %d Bearish, %d Netral", bullish, bearish, netral);

   string s = "Anda adalah analis teknikal dan ahli perdagangan futures profesional yang bertugas SEBAGAI HAKIM/PENYIMPUL.\n";
   s += StringFormat("Anda menerima TEPAT %d opini dari AI spesialis lain, masing-masing fokus di dimensi berbeda (trend, momentum, volatilitas, volume, support/resistance, smart money concept, price action, multi-timeframe, konteks makro, risk management). Bisa jadi ada yang berbeda pendapat.\n\n", opinionCount);
   s += StringFormat("Tally bias SUDAH DIHITUNG OTOMATIS OLEH SISTEM dari %d opini di atas (bukan tugas Anda menghitung ulang): %s. Pakai ini sebagai salah satu pertimbangan keputusan Anda.\n", opinionCount, tallyLine);
   s += "Tugas Anda:\n";
   s += "1. Timbang tally bias di atas, dan apakah indikator Volume mendukung indikator Trend.\n";
   s += StringFormat("2. Simpulkan jadi SATU keputusan tegas. Simbol: %s. Mode trading: %s.\n\n", symbol, tradeMode);
   s += "Gunakan bahasa Indonesia yang profesional, ringkas, dan langsung pada intinya.\n\n";
   s += "Format WAJIB jawaban (gunakan struktur ini persis):\n";
   s += "🎯 Keputusan: (BUY / SELL / WAIT)\n";
   s += "📊 Bias Arah: (Bullish / Bearish / Netral)\n";
   s += "📍 Level Kunci: (Support & Resistance utama)\n";
   s += "🎯 Skenario Entry: (area Long/Short)\n";
   s += "🛡️ Manajemen Risiko:\n";
   s += "- Stop-Loss: (WAJIB tulis HARGA ABSOLUT dulu, persis setelah tanda titik dua, baru boleh tambah penjelasan setelahnya)\n";
   s += "- Take-Profit: (format sama: HARGA ABSOLUT dulu, penjelasan setelahnya)\n";
   s += "📈 Probabilitas: (HANYA tulis perkiraan persentase keyakinan, misal \"±65%\")\n\n";
   s += StringFormat("Akhiri dengan satu kalimat: sebutkan ini hasil gabungan %d AI spesialis, berdasarkan probabilitas matematis, dan risiko sepenuhnya ditanggung trader.", opinionCount);
   s += BuildPillarWeightNote(alignedCount, dominant, trendBias, levelBias, momentumBias);
   return s;
  }

//+------------------------------------------------------------------+
//| Deteksi keputusan final (BUY/SELL/WAIT) dari teks AI Penyimpul.    |
//+------------------------------------------------------------------+
string DetectDecision(const string text)
  {
   string plain = text;
   StringReplace(plain, "*", "");
   int idx = StringFindCI(plain, "Keputusan:");
   if(idx < 0) return "";
   string tail = StringSubstr(plain, idx + StringLen("Keputusan:"));
   StringTrimLeft(tail);
   string tailUpper = tail; StringToUpper(tailUpper);
   if(StringFind(tailUpper, "BUY") == 0)  return "BUY";
   if(StringFind(tailUpper, "SELL") == 0) return "SELL";
   if(StringFind(tailUpper, "WAIT") == 0) return "WAIT";
   return "";
  }

//+------------------------------------------------------------------+
//| Parse 1 token angka mentah dari teks AI ke double, menangani gaya  |
//| koma ribuan ("63,084") vs koma desimal Indonesia ("4584,14").      |
//| SAMA logikanya dengan parsePriceString() di session_do.js.         |
//+------------------------------------------------------------------+
double ParsePriceToken(const string raw)
  {
   string cleaned = raw;
   StringReplace(cleaned, " ", "");
   if(cleaned == "") return -1;

   bool hasComma = StringFind(cleaned, ",") >= 0;
   bool hasDot   = StringFind(cleaned, ".") >= 0;

   if(hasComma && hasDot)
     {
      int lastComma = StringFindLast(cleaned, ",");
      int lastDot   = StringFindLast(cleaned, ".");
      if(lastComma > lastDot)
        {
         StringReplace(cleaned, ".", "");
         StringReplace(cleaned, ",", ".");
        }
      else
        {
         StringReplace(cleaned, ",", "");
        }
     }
   else if(hasComma)
     {
      int lastComma = StringFindLast(cleaned, ",");
      int digitsAfter = StringLen(cleaned) - lastComma - 1;
      if(digitsAfter == 3)
        {
         StringReplace(cleaned, ",", "");
        }
      else
        {
         string left = StringSubstr(cleaned, 0, lastComma);
         StringReplace(left, ",", "");
         string right = StringSubstr(cleaned, lastComma + 1);
         cleaned = left + "." + right;
        }
     }

   double val = StringToDouble(cleaned);
   return val;
  }

//+------------------------------------------------------------------+
//| Kumpulkan semua token angka di dalam sebuah potongan teks.         |
//+------------------------------------------------------------------+
void CollectNumberCandidates(const string window, double &candidates[])
  {
   ArrayResize(candidates, 0);
   string token = "";
   int len = StringLen(window);
   for(int i = 0; i <= len; i++)
     {
      ushort ch = (i < len) ? StringGetCharacter(window, i) : 0;
      bool isNumChar = (ch >= '0' && ch <= '9') || ch == '.' || ch == ',';
      if(isNumChar)
        {
         token += StringSubstr(window, i, 1);
        }
      else
        {
         if(StringLen(token) > 0)
           {
            double val = ParsePriceToken(token);
            if(val > 0)
              {
               int n = ArraySize(candidates);
               ArrayResize(candidates, n + 1);
               candidates[n] = val;
              }
           }
         token = "";
        }
     }
  }

//+------------------------------------------------------------------+
//| Ambil harga (Entry/SL/TP) yang mengikuti sebuah label di teks AI   |
//| Penyimpul. Balikin -1 kalau tidak ketemu. referencePrice dipakai   |
//| buat memilih kandidat angka paling masuk akal (dekat harga pasar). |
//+------------------------------------------------------------------+
double ExtractPriceAfterLabel(const string text, const string label, const double referencePrice)
  {
   string plain = text;
   StringReplace(plain, "*", "");

   int idx = StringFindCI(plain, label);
   if(idx < 0) return -1;
   int afterIdx = idx + StringLen(label);

   int remaining = StringLen(plain) - afterIdx;
   if(remaining <= 0) return -1;
   int windowLen = MathMin(200, remaining);
   string window = StringSubstr(plain, afterIdx, windowLen);

   // Potong di batas section berikutnya (kalau AI menyebut label lain
   // segera setelahnya di dalam 200 karakter yang sama).
   string boundaries[4] = {"Take-Profit", "Stop-Loss", "Manajemen Risiko", "Probabilitas"};
   int cut = StringLen(window);
   for(int i = 0; i < 4; i++)
     {
      int p = StringFindCI(window, boundaries[i]);
      if(p >= 0 && p < cut) cut = p;
     }
   window = StringSubstr(window, 0, cut);

   double candidates[];
   CollectNumberCandidates(window, candidates);
   if(ArraySize(candidates) == 0) return -1;

   if(referencePrice > 0)
     {
      double best = -1, bestDiff = DBL_MAX;
      for(int i = 0; i < ArraySize(candidates); i++)
        {
         double c = candidates[i];
         if(c >= referencePrice * 0.5 && c <= referencePrice * 1.5)
           {
            double diff = MathAbs(c - referencePrice);
            if(diff < bestDiff) { bestDiff = diff; best = c; }
           }
        }
      if(best > 0) return best;
     }
   return candidates[0]; // fallback: kandidat pertama yang ketemu
  }

//+------------------------------------------------------------------+
//| Block ringkasan sinyal ala "kode/terminal" (<pre>) -- SAMA         |
//| semangatnya dengan buildSignalCodeBlock() di session_do.js.        |
//+------------------------------------------------------------------+
string BuildSignalCodeBlock(const string symbol, const string decision, const double entry,
                             const double sl, const double tp, const int alignedCount, const string dominant)
  {
   if(decision == "") return "";

   string emoji = (decision == "BUY") ? "🟢" : (decision == "SELL") ? "🔴" : "🟡";
   string lines = emoji + " " + symbol + "  —  " + decision + "\n";

   bool hasRisk = (entry > 0 && sl > 0 && tp > 0);
   if(hasRisk)
     {
      lines += "─────────────────────\n";
      lines += "Entry : " + DoubleToString(entry, _Digits) + "\n";
      lines += "SL    : " + DoubleToString(sl, _Digits) + "  🔴\n";
      lines += "TP    : " + DoubleToString(tp, _Digits) + "  🟢\n";
      double risk = MathAbs(entry - sl);
      double reward = MathAbs(tp - entry);
      if(risk > 0)
         lines += "R:R   : 1 : " + DoubleToString(reward / risk, 2) + "\n";
     }

   lines += "─────────────────────\n";
   lines += "Pilar searah : " + IntegerToString(alignedCount) + "/3 (" + dominant + ")";

   return "<pre>" + EscapeHtml(lines) + "</pre>";
  }
//+------------------------------------------------------------------+
