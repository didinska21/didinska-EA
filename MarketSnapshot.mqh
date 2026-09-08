//+------------------------------------------------------------------+
//| MarketSnapshot.mqh                                                 |
//|                                                                    |
//| Ganti peran `dataPackage`/`buildDataSlice()` di versi JS -- tapi   |
//| DIAMBIL LANGSUNG dari feed broker lewat indicator handle native    |
//| MQL5 (iMA, iRSI, dst), BUKAN dari push candle 15 detik-an kayak    |
//| versi Python bridge. Ini yang bikin datanya "real-time betulan",   |
//| tanpa jeda apa pun.                                                |
//|                                                                    |
//| FASE 1 baru mencakup data buat 2 analis pertama (Trend & Momentum).|
//| Analis lain (Volatilitas/Bollinger, S&R, SMC, dst) NYUSUL di fase  |
//| berikutnya -- struct & fungsi ini akan ditambah field-nya, TIDAK   |
//| perlu dirombak ulang.                                              |
//+------------------------------------------------------------------+
#property strict

struct MarketSnapshot
  {
   double            lastPrice;
   double            ema20;
   double            ema50;
   double            ema200;
   double            rsi14;
   bool              valid; // false kalau ada indikator yang gagal diambil
  };

// Handle indikator dibuat SEKALI di OnInit (bukan tiap kali butuh data --
// itu praktik yang salah di MQL5, bisa bikin memory leak/limit handle
// kepakai abis kalau dibuat ulang tiap tick/timer).
int g_handleEma20  = INVALID_HANDLE;
int g_handleEma50  = INVALID_HANDLE;
int g_handleEma200 = INVALID_HANDLE;
int g_handleRsi14  = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Buat semua indicator handle yang dibutuhkan. Panggil 1x di         |
//| OnInit(). Balikin false kalau ada yang gagal dibuat (misal symbol/ |
//| timeframe tidak valid) -- EA harus berhenti kalau ini gagal.       |
//+------------------------------------------------------------------+
bool MarketSnapshot_Init(const string symbol, const ENUM_TIMEFRAMES timeframe)
  {
   g_handleEma20  = iMA(symbol, timeframe, 20,  0, MODE_EMA, PRICE_CLOSE);
   g_handleEma50  = iMA(symbol, timeframe, 50,  0, MODE_EMA, PRICE_CLOSE);
   g_handleEma200 = iMA(symbol, timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
   g_handleRsi14  = iRSI(symbol, timeframe, 14, PRICE_CLOSE);

   if(g_handleEma20 == INVALID_HANDLE || g_handleEma50 == INVALID_HANDLE ||
      g_handleEma200 == INVALID_HANDLE || g_handleRsi14 == INVALID_HANDLE)
     {
      Print("[MarketSnapshot] Gagal membuat 1 atau lebih indicator handle. Cek symbol/timeframe.");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Lepas semua indicator handle. Panggil 1x di OnDeinit().            |
//+------------------------------------------------------------------+
void MarketSnapshot_Deinit()
  {
   if(g_handleEma20  != INVALID_HANDLE) IndicatorRelease(g_handleEma20);
   if(g_handleEma50  != INVALID_HANDLE) IndicatorRelease(g_handleEma50);
   if(g_handleEma200 != INVALID_HANDLE) IndicatorRelease(g_handleEma200);
   if(g_handleRsi14  != INVALID_HANDLE) IndicatorRelease(g_handleRsi14);
  }

//+------------------------------------------------------------------+
//| Ambil nilai TERBARU (candle yang sudah CLOSE, index 1 -- BUKAN     |
//| index 0 yang candle berjalan/belum tutup, biar konsisten sama cara |
//| versi JS baca candle "closed") dari 1 indicator handle.            |
//+------------------------------------------------------------------+
bool CopyLatestValue(int handle, double &outValue)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, 1, 1, buf) != 1)
      return false;
   outValue = buf[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Ambil snapshot data pasar terbaru. Balikin struct dengan           |
//| `valid=false` kalau salah satu data gagal diambil (misal history   |
//| belum cukup ter-load) -- caller HARUS cek `valid` sebelum          |
//| dipakai.                                                            |
//+------------------------------------------------------------------+
MarketSnapshot MarketSnapshot_Get(const string symbol)
  {
   MarketSnapshot snap;
   snap.valid = true;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
     {
      snap.valid = false;
      return snap;
     }
   snap.lastPrice = tick.bid;

   if(!CopyLatestValue(g_handleEma20, snap.ema20))   snap.valid = false;
   if(!CopyLatestValue(g_handleEma50, snap.ema50))   snap.valid = false;
   if(!CopyLatestValue(g_handleEma200, snap.ema200)) snap.valid = false;
   if(!CopyLatestValue(g_handleRsi14, snap.rsi14))   snap.valid = false;

   return snap;
  }
//+------------------------------------------------------------------+
