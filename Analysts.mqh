//+------------------------------------------------------------------+
//| Analysts.mqh                                                       |
//|                                                                    |
//| FASE 2 -- 10 analis lengkap, diadaptasi 1:1 (system prompt SAMA    |
//| PERSIS teksnya sebisa mungkin) dari src/analysts.js, supaya        |
//| kualitas hasil AI konsisten dengan versi Worker yang sudah         |
//| terbukti bagus. Data slice-nya disesuaikan dengan yang TERSEDIA    |
//| native lewat MarketSnapshot.mqh (lihat catatan keterbatasan di     |
//| MarketSnapshot.mqh).                                               |
//|                                                                    |
//| PILLAR_MAP (identik dengan mode "lengkap" di analysts.js):         |
//|   trend    = [AI 1]                                                |
//|   level    = [AI 5, AI 6]                                          |
//|   momentum = [AI 2, AI 7]                                          |
//| AI 3,4,8,9,10 = PENUNJANG/VALIDATOR (tidak menentukan arah).        |
//+------------------------------------------------------------------+
#property strict
#include "MarketSnapshot.mqh"

#define ANALYST_COUNT 10

//+------------------------------------------------------------------+
//| Judul tiap analis -- dipakai buat label progres Telegram & label   |
//| opini yang dikirim ke Penyimpul ("AI n (Judul)").                  |
//+------------------------------------------------------------------+
string AnalystTitle(const int number)
  {
   switch(number)
     {
      case 1:  return "Spesialis Trend (Moving Averages)";
      case 2:  return "Spesialis Momentum (Oscillators)";
      case 3:  return "Spesialis Volatilitas (Bands & ATR)";
      case 4:  return "Spesialis Volume (Aliran Uang)";
      case 5:  return "Spesialis Support & Resistance";
      case 6:  return "Spesialis Smart Money Concepts (SMC)";
      case 7:  return "Spesialis Price Action (Candlestick)";
      case 8:  return "Spesialis Multi-Timeframe (MTF) Alignment";
      case 9:  return "Spesialis Konteks Makro";
      case 10: return "Spesialis Risk Management";
     }
   return "Analis Tidak Dikenal";
  }

//+------------------------------------------------------------------+
//| Balikin catatan peran pilar -- SAMA PERSIS teksnya dengan          |
//| pillarRoleNote() di analysts.js.                                   |
//+------------------------------------------------------------------+
string PillarRoleNote(const string pillar)
  {
   if(pillar == "supporting")
      return "PERAN ANDA: Analis Pendukung dalam strategi \"Konfluensi 3 Pilar\". Opini Anda TIDAK menentukan arah sinyal utama — tugas Anda MENDUKUNG atau MEMBERI PERINGATAN terhadap 3 pilar utama (Trend, Level Kunci, Momentum). Jangan berperilaku seolah opini Anda setara bobotnya dengan AI pilar utama.";

   string label = "";
   if(pillar == "trend")    label = "PILAR 1 — TREND (arah besar pasar)";
   if(pillar == "level")    label = "PILAR 2 — LEVEL KUNCI (zona reaksi harga)";
   if(pillar == "momentum") label = "PILAR 3 — MOMENTUM / KONFIRMASI ENTRY";

   return "PERAN ANDA: pemegang " + label + ", salah satu dari 3 PILAR UTAMA strategi \"Konfluensi 3 Pilar\". Bias arah Anda IKUT MENENTUKAN keputusan akhir secara langsung — sistem akan mengecek apakah ke-3 pilar (Trend, Level Kunci, Momentum) SEARAH sebelum memutuskan sinyal kuat atau WAIT. Jangan ragu-ragu di baris \"Bias:\" — beri kesimpulan tegas berdasar data.";
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
//| Helper: bangun array JSON candle OHLC dari MarketSnapshot.         |
//+------------------------------------------------------------------+
string BuildCandleArrayJson(const MarketSnapshot &snap)
  {
   string s = "[";
   for(int i = 0; i < MS_CANDLE_COUNT; i++)
     {
      if(i > 0) s += ",";
      s += StringFormat("{\"open\":%.2f,\"high\":%.2f,\"low\":%.2f,\"close\":%.2f}",
                         snap.candleOpen[i], snap.candleHigh[i], snap.candleLow[i], snap.candleClose[i]);
     }
   s += "]";
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
//+------------------------------------------------------------------+
string BuildMomentumSystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Momentum (Oscillators)", symbol, tradeMode, "momentum");
   s += "\nTugas: baca RSI, MACD, dan Stochastic. Nilai apakah pergerakan harga didukung momentum kuat, atau ada indikasi Divergence (sinyal pembalikan). Sebagai bagian PILAR 3 (Momentum/Konfirmasi), fokus jawab: apakah momentum saat ini MENGKONFIRMASI entry ke arah tertentu SEKARANG, bukan cuma arah umum jangka panjang.";
   return s;
  }

string BuildMomentumDataJson(const MarketSnapshot &snap)
  {
   return StringFormat("{\"rsi14\":%.2f,\"macd\":{\"main\":%.4f,\"signal\":%.4f,\"histogram\":%.4f},\"stochastic\":{\"main\":%.2f,\"signal\":%.2f}}",
                        snap.rsi14, snap.macdMain, snap.macdSignal, snap.macdHist, snap.stochMain, snap.stochSignal);
  }

//+------------------------------------------------------------------+
//| ANALIS #3 -- Spesialis Volatilitas (Bands & ATR). Penunjang.       |
//+------------------------------------------------------------------+
string BuildVolatilitySystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Volatilitas (Bands & ATR)", symbol, tradeMode, "supporting");
   s += "\nTugas: analisa Bollinger Bands & ATR. Ukur seberapa liar pergerakan harga, dan deteksi potensi breakout kalau bands menyempit (squeeze). Sebutkan juga apakah volatilitas saat ini mendukung entry AMAN (tidak terlalu liar) atau berisiko tinggi (whipsaw).";
   return s;
  }

string BuildVolatilityDataJson(const MarketSnapshot &snap)
  {
   return StringFormat("{\"lastPrice\":%.2f,\"bollinger\":{\"upper\":%.2f,\"middle\":%.2f,\"lower\":%.2f},\"atr14\":%.2f}",
                        snap.lastPrice, snap.bbUpper, snap.bbMiddle, snap.bbLower, snap.atr14);
  }

//+------------------------------------------------------------------+
//| ANALIS #4 -- Spesialis Volume (Aliran Uang). Penunjang.            |
//+------------------------------------------------------------------+
string BuildVolumeSystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Volume (Aliran Uang)", symbol, tradeMode, "supporting");
   s += "\nTugas: baca On-Balance Volume (OBV). Konfirmasi apakah pergerakan harga didukung volume besar (valid) atau lemah (indikasi fakeout).\n";
   s += "CATATAN: \"volume\" di sini adalah TICK VOLUME dari MT5 (jumlah perubahan harga), BUKAN volume transaksi riil (pasar OTC, tidak ada bursa tunggal yang bisa kasih volume pasti). Beri opini dengan keyakinan LEBIH RENDAH dibanding kalau ini data bursa dengan volume riil.";
   return s;
  }

string BuildVolumeDataJson(const MarketSnapshot &snap)
  {
   return StringFormat("{\"obv\":%.2f,\"lastPrice\":%.2f}", snap.obv, snap.lastPrice);
  }

//+------------------------------------------------------------------+
//| ANALIS #5 -- Spesialis Support & Resistance. Pilar UTAMA (Level).  |
//+------------------------------------------------------------------+
string BuildSrSystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Support & Resistance", symbol, tradeMode, "level");
   s += "\nTugas: identifikasi level kunci historis, Pivot Points, dan Fibonacci Retracement. Sebagai pemegang PILAR 2 (Level Kunci), WAJIB tegaskan: apakah harga SEKARANG sedang berada di/dekat zona reaksi (support/resistance/pivot/fibo), atau justru di tengah kekosongan (no man's land) — sinyal entry jauh lebih valid kalau dekat level kunci.";
   return s;
  }

string BuildSrDataJson(const MarketSnapshot &snap)
  {
   return StringFormat(
      "{\"lastPrice\":%.2f,\"supportResistanceHistoris\":{\"support\":%.2f,\"resistance\":%.2f},"
      "\"pivotPoints\":{\"p\":%.2f,\"r1\":%.2f,\"r2\":%.2f,\"s1\":%.2f,\"s2\":%.2f},"
      "\"fibonacci\":{\"direction\":\"%s\",\"swingHigh\":%.2f,\"swingLow\":%.2f,\"level382\":%.2f,\"level500\":%.2f,\"level618\":%.2f}}",
      snap.lastPrice, snap.srSupport, snap.srResistance,
      snap.pivotP, snap.pivotR1, snap.pivotR2, snap.pivotS1, snap.pivotS2,
      snap.fiboDirection, snap.fiboSwingHigh, snap.fiboSwingLow, snap.fibo382, snap.fibo500, snap.fibo618);
  }

//+------------------------------------------------------------------+
//| ANALIS #6 -- Spesialis Smart Money Concepts (SMC). Pilar UTAMA (Level). |
//+------------------------------------------------------------------+
string BuildSmcSystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Smart Money Concepts (SMC)", symbol, tradeMode, "level");
   s += "\nTugas: cari Order Block, Fair Value Gap (FVG)/imbalance, Liquidity Grab, dan Break of Structure (BoS). Sebagai bagian PILAR 2 (Level Kunci) bersama AI Support/Resistance, fokus: apakah harga sekarang berada di zona institusional (Order Block/FVG) yang jadi acuan reaksi harga.\n";
   s += "CATATAN: data SMC ini hasil heuristik otomatis, bukan deteksi sempurna -- nilai kewajarannya. Field bertipe \"none\" berarti pola itu tidak terdeteksi di data saat ini, jangan mengarang.";
   return s;
  }

string BuildSmcDataJson(const MarketSnapshot &snap)
  {
   return StringFormat(
      "{\"lastPrice\":%.2f,"
      "\"orderBlock\":{\"type\":\"%s\",\"high\":%.2f,\"low\":%.2f},"
      "\"fairValueGap\":{\"type\":\"%s\",\"top\":%.2f,\"bottom\":%.2f},"
      "\"breakOfStructure\":\"%s\","
      "\"liquidityGrab\":{\"detected\":%s,\"type\":\"%s\"}}",
      snap.lastPrice,
      snap.smcOrderBlockType, snap.smcOrderBlockHigh, snap.smcOrderBlockLow,
      snap.smcFvgType, snap.smcFvgTop, snap.smcFvgBottom,
      snap.smcBosType,
      (snap.smcLiquidityGrab ? "true" : "false"), snap.smcLiquidityType);
  }

//+------------------------------------------------------------------+
//| ANALIS #7 -- Spesialis Price Action (Candlestick, dari data OHLC). |
//| Pilar UTAMA (Momentum). Versi EA ini pakai OHLC mentah (BUKAN      |
//| foto chart -- EA tidak punya kemampuan kirim/baca gambar), sama    |
//| seperti fallback yang disebut di komentar analysts.js.             |
//+------------------------------------------------------------------+
string BuildPriceActionSystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Price Action (Candlestick)", symbol, tradeMode, "momentum");
   s += "\nTugas: baca deretan candle OHLC mentah (open/high/low/close) beberapa candle terakhir (index 0 = candle PALING BARU/paling akhir array). Identifikasi pola candlestick yang relevan (misal Bullish/Bearish Engulfing, Pin Bar/Hammer, Doji, Shooting Star, Marubozu). Sebagai bagian PILAR 3 (Momentum/Konfirmasi) bersama AI Momentum, fokus: apakah pola candle ini MENGKONFIRMASI entry sekarang atau justru memberi sinyal ragu (indecision candle).";
   return s;
  }

string BuildPriceActionDataJson(const MarketSnapshot &snap)
  {
   return StringFormat("{\"candleTerakhir\":%s,\"lastPrice\":%.2f}", BuildCandleArrayJson(snap), snap.lastPrice);
  }

//+------------------------------------------------------------------+
//| ANALIS #8 -- Spesialis Multi-Timeframe (MTF) Alignment. Penunjang. |
//+------------------------------------------------------------------+
string BuildMtfSystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Multi-Timeframe (MTF) Alignment", symbol, tradeMode, "supporting");
   s += "\nTugas: bandingkan tren di timeframe utama vs timeframe lebih besar (HTF). Kalau HTF Bearish tapi timeframe utama Bullish (atau sebaliknya), beri PERINGATAN risiko tinggi karena melawan tren besar.";
   return s;
  }

string BuildMtfDataJson(const MarketSnapshot &snap, const string primaryLabel, const string htfLabel)
  {
   return StringFormat(
      "{\"timeframeUtama\":\"%s\",\"timeframeBesar\":\"%s\","
      "\"trendTimeframeUtama\":{\"lastPrice\":%.2f,\"ema20\":%.2f,\"ema50\":%.2f},"
      "\"trendTimeframeBesar\":{\"lastPrice\":%.2f,\"ema20\":%.2f,\"ema50\":%.2f,\"ema200\":%.2f}}",
      primaryLabel, htfLabel,
      snap.lastPrice, snap.ema20, snap.ema50,
      snap.htfLastClose, snap.htfEma20, snap.htfEma50, snap.htfEma200);
  }

//+------------------------------------------------------------------+
//| ANALIS #9 -- Spesialis Konteks Makro. Penunjang.                   |
//| Data makro kripto (BTC Dominance/Fear&Greed) TIDAK tersedia native |
//| di MQL5 -- selalu notApplicable=true (lihat MarketSnapshot.mqh).   |
//+------------------------------------------------------------------+
string BuildMacroSystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Konteks Makro", symbol, tradeMode, "supporting");
   s += "\nTugas: nilai sentimen pasar secara umum dari BTC Dominance & Fear/Greed Index (data khusus kripto). Kalau field \"notApplicable\" bernilai true, JANGAN memaksakan opini dari data itu -- cukup sebutkan data makro ini tidak relevan untuk simbol ini, dan beri \"Bias: Netral\" untuk dimensi ini saja.";
   return s;
  }

string BuildMacroDataJson(const MarketSnapshot &snap)
  {
   return StringFormat("{\"notApplicable\":%s}", (snap.macroNotApplicable ? "true" : "false"));
  }

//+------------------------------------------------------------------+
//| ANALIS #10 -- Spesialis Risk Management. Penunjang.                |
//+------------------------------------------------------------------+
string BuildRiskSystemPrompt(const string symbol, const string tradeMode)
  {
   string s = BaseHeader("Spesialis Risk Management", symbol, tradeMode, "supporting");
   s += "\nTugas: JANGAN menebak arah pasar. Fokus RUMUSKAN trading plan: usulan jarak Stop-Loss logis berbasis ATR (misal 1.5x ATR dari harga saat ini), usulan Take-Profit (misal 2-3x jarak SL), dan rasio Risk:Reward minimum yang wajar untuk mode trading ini.";
   return s;
  }

string BuildRiskDataJson(const MarketSnapshot &snap, const string tradeMode)
  {
   return StringFormat("{\"lastPrice\":%.2f,\"atr14\":%.2f,\"tradeMode\":\"%s\"}",
                        snap.lastPrice, snap.atr14, tradeMode);
  }

//+------------------------------------------------------------------+
//| Cari baris "Bias: Bullish/Bearish/Netral" di jawaban AI.           |
//+------------------------------------------------------------------+
string ExtractBiasFromOpinion(const string opinionText)
  {
   int pos = StringFind(opinionText, "Bias:");
   if(pos < 0)
      return "Netral"; // fallback aman kalau AI lupa format
   string tail = StringSubstr(opinionText, pos + StringLen("Bias:"));
   StringTrimLeft(tail);
   StringTrimRight(tail);
   int lineEnd = StringFind(tail, "\n");
   if(lineEnd >= 0)
      tail = StringSubstr(tail, 0, lineEnd);
   StringTrimRight(tail);
   // Normalisasi -- kalau AI nulis embel-embel lain di baris itu, ambil kata pertama saja.
   if(StringFind(tail, "Bullish") == 0) return "Bullish";
   if(StringFind(tail, "Bearish") == 0) return "Bearish";
   return "Netral";
  }
//+------------------------------------------------------------------+
