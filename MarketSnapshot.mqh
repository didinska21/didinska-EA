//+------------------------------------------------------------------+
//| MarketSnapshot.mqh                                                 |
//|                                                                    |
//| FASE 2 -- lengkap untuk 10 analis + 1 Penyimpul. Semua data        |
//| diambil NATIVE dari indicator handle & history MQL5 (bukan bridge  |
//| Python) -- jadi real-time betulan.                                 |
//|                                                                    |
//| CATATAN KETERBATASAN vs versi JS (src/analysts.js):                |
//| - Volume: MT5 cuma punya TICK VOLUME (jumlah perubahan harga),     |
//|   BUKAN volume transaksi riil (forex/CFD OTC, tidak ada bursa      |
//|   tunggal). Sama seperti catatan JS untuk simbol MT5 -- opini AI   |
//|   Volume WAJIB dikasih keyakinan lebih rendah (diinstruksikan di   |
//|   system prompt-nya, lihat Analysts.mqh).                          |
//| - Makro (BTC Dominance / Fear&Greed Index): TIDAK tersedia lewat   |
//|   indicator handle MQL5 -- selalu ditandai notApplicable=true      |
//|   (identik dengan perlakuan JS untuk simbol MT5/XAUUSD).           |
//| - SMC (Order Block/FVG/BoS/Liquidity Grab): heuristik sederhana    |
//|   dari price action mentah, BUKAN deteksi sempurna -- sama seperti |
//|   catatan di JS aslinya ("nilai kewajarannya").                    |
//+------------------------------------------------------------------+
#property strict

#define MS_CANDLE_COUNT 15   // jumlah candle OHLC terakhir buat analis Price Action
#define MS_SR_LOOKBACK  50   // lookback (bar) buat Support/Resistance historis
#define MS_FIBO_LOOKBACK 100 // lookback (bar) buat cari swing high/low Fibonacci
#define MS_SMC_LOOKBACK 30   // lookback (bar) buat heuristik SMC

struct MarketSnapshot
  {
   double            lastPrice;

   // --- Analis #1 Trend ---
   double            ema20;
   double            ema50;
   double            ema200;

   // --- Analis #2 Momentum ---
   double            rsi14;
   double            macdMain;
   double            macdSignal;
   double            macdHist;
   double            stochMain;
   double            stochSignal;

   // --- Analis #3 Volatilitas ---
   double            bbUpper;
   double            bbMiddle;
   double            bbLower;
   double            atr14;

   // --- Analis #4 Volume ---
   double            obv;

   // --- Analis #5 Support & Resistance ---
   double            srSupport;
   double            srResistance;
   double            pivotP;
   double            pivotR1;
   double            pivotR2;
   double            pivotS1;
   double            pivotS2;
   string            fiboDirection; // "retracement_turun" / "retracement_naik"
   double            fiboSwingHigh;
   double            fiboSwingLow;
   double            fibo382;
   double            fibo500;
   double            fibo618;

   // --- Analis #6 Smart Money Concepts (heuristik) ---
   string            smcOrderBlockType; // "bullish" / "bearish" / "none"
   double            smcOrderBlockHigh;
   double            smcOrderBlockLow;
   string            smcFvgType;        // "bullish" / "bearish" / "none"
   double            smcFvgTop;
   double            smcFvgBottom;
   string            smcBosType;        // "bullish" / "bearish" / "none"
   bool              smcLiquidityGrab;
   string            smcLiquidityType;  // "buy_side" / "sell_side" / "none"

   // --- Analis #7 Price Action (candle OHLC mentah, ganti versi foto) ---
   double            candleOpen[MS_CANDLE_COUNT];
   double            candleHigh[MS_CANDLE_COUNT];
   double            candleLow[MS_CANDLE_COUNT];
   double            candleClose[MS_CANDLE_COUNT];

   // --- Analis #8 Multi-Timeframe ---
   double            htfEma20;
   double            htfEma50;
   double            htfEma200;
   double            htfLastClose;

   // --- Analis #9 Makro ---
   bool              macroNotApplicable;

   bool              valid; // false kalau ada indikator yang gagal diambil
  };

// Handle indikator dibuat SEKALI di OnInit.
int g_handleEma20     = INVALID_HANDLE;
int g_handleEma50     = INVALID_HANDLE;
int g_handleEma200    = INVALID_HANDLE;
int g_handleRsi14     = INVALID_HANDLE;
int g_handleMacd      = INVALID_HANDLE;
int g_handleStoch     = INVALID_HANDLE;
int g_handleBands     = INVALID_HANDLE;
int g_handleAtr14     = INVALID_HANDLE;
int g_handleObv       = INVALID_HANDLE;
int g_handleHtfEma20  = INVALID_HANDLE;
int g_handleHtfEma50  = INVALID_HANDLE;
int g_handleHtfEma200 = INVALID_HANDLE;

ENUM_TIMEFRAMES g_msTimeframe    = PERIOD_M15;
ENUM_TIMEFRAMES g_msHtfTimeframe = PERIOD_H1;

//+------------------------------------------------------------------+
//| Buat semua indicator handle. Panggil 1x di OnInit().               |
//+------------------------------------------------------------------+
bool MarketSnapshot_Init(const string symbol, const ENUM_TIMEFRAMES timeframe, const ENUM_TIMEFRAMES htfTimeframe)
  {
   g_msTimeframe    = timeframe;
   g_msHtfTimeframe = htfTimeframe;

   g_handleEma20  = iMA(symbol, timeframe, 20,  0, MODE_EMA, PRICE_CLOSE);
   g_handleEma50  = iMA(symbol, timeframe, 50,  0, MODE_EMA, PRICE_CLOSE);
   g_handleEma200 = iMA(symbol, timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
   g_handleRsi14  = iRSI(symbol, timeframe, 14, PRICE_CLOSE);
   g_handleMacd   = iMACD(symbol, timeframe, 12, 26, 9, PRICE_CLOSE);
   g_handleStoch  = iStochastic(symbol, timeframe, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   g_handleBands  = iBands(symbol, timeframe, 20, 0, 2.0, PRICE_CLOSE);
   g_handleAtr14  = iATR(symbol, timeframe, 14);
   g_handleObv    = iOBV(symbol, timeframe, VOLUME_TICK);

   g_handleHtfEma20  = iMA(symbol, htfTimeframe, 20,  0, MODE_EMA, PRICE_CLOSE);
   g_handleHtfEma50  = iMA(symbol, htfTimeframe, 50,  0, MODE_EMA, PRICE_CLOSE);
   g_handleHtfEma200 = iMA(symbol, htfTimeframe, 200, 0, MODE_EMA, PRICE_CLOSE);

   if(g_handleEma20==INVALID_HANDLE || g_handleEma50==INVALID_HANDLE || g_handleEma200==INVALID_HANDLE ||
      g_handleRsi14==INVALID_HANDLE || g_handleMacd==INVALID_HANDLE || g_handleStoch==INVALID_HANDLE ||
      g_handleBands==INVALID_HANDLE || g_handleAtr14==INVALID_HANDLE || g_handleObv==INVALID_HANDLE ||
      g_handleHtfEma20==INVALID_HANDLE || g_handleHtfEma50==INVALID_HANDLE || g_handleHtfEma200==INVALID_HANDLE)
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
   int handles[] = { g_handleEma20, g_handleEma50, g_handleEma200, g_handleRsi14, g_handleMacd,
                      g_handleStoch, g_handleBands, g_handleAtr14, g_handleObv,
                      g_handleHtfEma20, g_handleHtfEma50, g_handleHtfEma200 };
   for(int i = 0; i < ArraySize(handles); i++)
      if(handles[i] != INVALID_HANDLE) IndicatorRelease(handles[i]);
  }

//+------------------------------------------------------------------+
//| Ambil nilai TERBARU (candle sudah CLOSE, index 1) dari 1 buffer.   |
//+------------------------------------------------------------------+
bool CopyLatestValue(int handle, int bufferIndex, double &outValue)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, bufferIndex, 1, 1, buf) != 1)
      return false;
   outValue = buf[0];
   return true;
  }

bool CopyLatestValue(int handle, double &outValue) { return CopyLatestValue(handle, 0, outValue); }

//+------------------------------------------------------------------+
//| Support/Resistance historis sederhana: high tertinggi & low        |
//| terendah dalam N bar terakhir (candle sudah closed, index 1..N).   |
//+------------------------------------------------------------------+
bool ComputeSupportResistance(const string symbol, const ENUM_TIMEFRAMES timeframe, const int lookback,
                               double &support, double &resistance)
  {
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   if(CopyHigh(symbol, timeframe, 1, lookback, highs) != lookback) return false;
   if(CopyLow(symbol, timeframe, 1, lookback, lows) != lookback) return false;

   resistance = highs[ArrayMaximum(highs, 0, lookback)];
   support    = lows[ArrayMinimum(lows, 0, lookback)];
   return true;
  }

//+------------------------------------------------------------------+
//| Pivot Points klasik dari H/L/C hari SEBELUMNYA (D1, index 1).      |
//+------------------------------------------------------------------+
bool ComputePivotPoints(const string symbol, double &p, double &r1, double &r2, double &s1, double &s2)
  {
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   if(CopyHigh(symbol, PERIOD_D1, 1, 1, high) != 1) return false;
   if(CopyLow(symbol, PERIOD_D1, 1, 1, low) != 1) return false;
   if(CopyClose(symbol, PERIOD_D1, 1, 1, close) != 1) return false;

   double h = high[0], l = low[0], c = close[0];
   p  = (h + l + c) / 3.0;
   r1 = 2.0 * p - l;
   s1 = 2.0 * p - h;
   r2 = p + (h - l);
   s2 = p - (h - l);
   return true;
  }

//+------------------------------------------------------------------+
//| Fibonacci Retracement -- arah otomatis dari swing high/low         |
//| terbaru dalam N bar terakhir (SAMA logikanya dengan komentar di    |
//| src/analysts.js): kalau swing high LEBIH BARU dari swing low,      |
//| berarti abis naik -> "retracement_turun" (cari support koreksi).  |
//| Kalau swing low lebih baru -> "retracement_naik" (cari resistance  |
//| koreksi).                                                          |
//+------------------------------------------------------------------+
bool ComputeFibonacci(const string symbol, const ENUM_TIMEFRAMES timeframe, const int lookback,
                      string &direction, double &swingHigh, double &swingLow,
                      double &f382, double &f500, double &f618)
  {
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   if(CopyHigh(symbol, timeframe, 1, lookback, highs) != lookback) return false;
   if(CopyLow(symbol, timeframe, 1, lookback, lows) != lookback) return false;

   int idxHigh = ArrayMaximum(highs, 0, lookback); // index 0 = paling baru
   int idxLow  = ArrayMinimum(lows, 0, lookback);

   swingHigh = highs[idxHigh];
   swingLow  = lows[idxLow];
   double range = swingHigh - swingLow;

   if(idxHigh < idxLow)
     {
      // swing high lebih baru (index lebih kecil = lebih dekat ke sekarang)
      direction = "retracement_turun";
      f382 = swingHigh - range * 0.382;
      f500 = swingHigh - range * 0.5;
      f618 = swingHigh - range * 0.618;
     }
   else
     {
      direction = "retracement_naik";
      f382 = swingLow + range * 0.382;
      f500 = swingLow + range * 0.5;
      f618 = swingLow + range * 0.618;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Heuristik Smart Money Concepts sederhana dari MS_SMC_LOOKBACK bar  |
//| terakhir: Order Block, Fair Value Gap (FVG), Break of Structure    |
//| (BoS), dan Liquidity Grab. INI BUKAN deteksi sempurna -- cukup     |
//| buat kasih AI SMC "bahan mentah" yang wajar, sama semangatnya      |
//| dengan versi JS ("nilai kewajarannya").                            |
//+------------------------------------------------------------------+
void ComputeSmc(const string symbol, const ENUM_TIMEFRAMES timeframe, MarketSnapshot &snap)
  {
   snap.smcOrderBlockType = "none";
   snap.smcOrderBlockHigh = 0;
   snap.smcOrderBlockLow  = 0;
   snap.smcFvgType   = "none";
   snap.smcFvgTop    = 0;
   snap.smcFvgBottom = 0;
   snap.smcBosType   = "none";
   snap.smcLiquidityGrab = false;
   snap.smcLiquidityType = "none";

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int n = CopyRates(symbol, timeframe, 1, MS_SMC_LOOKBACK, rates); // index1..N, sudah closed
   if(n < 10) return; // data kurang, biarkan default "none"

   // --- FVG (Fair Value Gap / imbalance 3-candle) -- cari yang PALING BARU.
   // rates[i] = candle ke-(i+1) dari sekarang (index0 = candle closed paling baru).
   // Bullish FVG: low candle[i] > high candle[i+2] (ada celah antara candle
   // "tengah" yang breakout naik dan candle 2 bar sebelumnya).
   // Bearish FVG: high candle[i] < low candle[i+2].
   for(int i = 0; i <= n - 3; i++)
     {
      if(rates[i].low > rates[i+2].high)
        {
         snap.smcFvgType   = "bullish";
         snap.smcFvgBottom = rates[i+2].high;
         snap.smcFvgTop    = rates[i].low;
         break;
        }
      if(rates[i].high < rates[i+2].low)
        {
         snap.smcFvgType = "bearish";
         snap.smcFvgTop    = rates[i+2].low;
         snap.smcFvgBottom = rates[i].high;
         break;
        }
     }

   // --- Order Block: candle berlawanan arah TERAKHIR sebelum pergerakan
   // kuat (breakout) yang searah. Bullish OB = candle bearish (close<open)
   // yang diikuti candle bullish besar menembus high-nya. Bearish OB =
   // kebalikannya. Dicari dari yang PALING BARU.
   for(int i = 1; i <= n - 2; i++)
     {
      // rates[i] = candle kandidat OB, rates[i-1] = candle setelahnya (lebih baru)
      bool candleIsBear = rates[i].close < rates[i].open;
      bool candleIsBull = rates[i].close > rates[i].open;
      bool nextBreaksUp   = rates[i-1].close > rates[i].high && rates[i-1].close > rates[i-1].open;
      bool nextBreaksDown = rates[i-1].close < rates[i].low  && rates[i-1].close < rates[i-1].open;

      if(candleIsBear && nextBreaksUp)
        {
         snap.smcOrderBlockType = "bullish";
         snap.smcOrderBlockHigh = rates[i].high;
         snap.smcOrderBlockLow  = rates[i].low;
         break;
        }
      if(candleIsBull && nextBreaksDown)
        {
         snap.smcOrderBlockType = "bearish";
         snap.smcOrderBlockHigh = rates[i].high;
         snap.smcOrderBlockLow  = rates[i].low;
         break;
        }
     }

   // --- Break of Structure (BoS): harga PENUTUPAN candle paling baru
   // menembus swing high/low dari N-1 candle sebelumnya.
   double priorHigh = rates[1].high, priorLow = rates[1].low;
   for(int i = 2; i < n; i++)
     {
      if(rates[i].high > priorHigh) priorHigh = rates[i].high;
      if(rates[i].low  < priorLow)  priorLow  = rates[i].low;
     }
   if(rates[0].close > priorHigh) snap.smcBosType = "bullish";
   else if(rates[0].close < priorLow) snap.smcBosType = "bearish";

   // --- Liquidity Grab: candle paling baru bikin wick TEMBUS swing
   // high/low sebelumnya tapi CLOSE balik ke dalam range (sweep).
   if(rates[0].high > priorHigh && rates[0].close < priorHigh)
     {
      snap.smcLiquidityGrab = true;
      snap.smcLiquidityType = "buy_side"; // nyapu stop-loss di atas (buy-side liquidity)
     }
   else if(rates[0].low < priorLow && rates[0].close > priorLow)
     {
      snap.smcLiquidityGrab = true;
      snap.smcLiquidityType = "sell_side";
     }
  }

//+------------------------------------------------------------------+
//| Ambil snapshot data pasar terbaru untuk SEMUA 10 analis.           |
//+------------------------------------------------------------------+
MarketSnapshot MarketSnapshot_Get(const string symbol)
  {
   MarketSnapshot snap;
   snap.valid = true;
   snap.macroNotApplicable = true; // lihat catatan keterbatasan di header file ini

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick)) { snap.valid = false; return snap; }
   snap.lastPrice = tick.bid;

   if(!CopyLatestValue(g_handleEma20, snap.ema20))   snap.valid = false;
   if(!CopyLatestValue(g_handleEma50, snap.ema50))   snap.valid = false;
   if(!CopyLatestValue(g_handleEma200, snap.ema200)) snap.valid = false;
   if(!CopyLatestValue(g_handleRsi14, snap.rsi14))   snap.valid = false;

   // iMACD buffer: 0=MAIN, 1=SIGNAL
   if(!CopyLatestValue(g_handleMacd, 0, snap.macdMain))   snap.valid = false;
   if(!CopyLatestValue(g_handleMacd, 1, snap.macdSignal)) snap.valid = false;
   snap.macdHist = snap.macdMain - snap.macdSignal;

   // iStochastic buffer: 0=MAIN (%K), 1=SIGNAL (%D)
   if(!CopyLatestValue(g_handleStoch, 0, snap.stochMain))   snap.valid = false;
   if(!CopyLatestValue(g_handleStoch, 1, snap.stochSignal)) snap.valid = false;

   // iBands buffer: 0=BASE(middle), 1=UPPER, 2=LOWER
   if(!CopyLatestValue(g_handleBands, 0, snap.bbMiddle)) snap.valid = false;
   if(!CopyLatestValue(g_handleBands, 1, snap.bbUpper))  snap.valid = false;
   if(!CopyLatestValue(g_handleBands, 2, snap.bbLower))  snap.valid = false;

   if(!CopyLatestValue(g_handleAtr14, snap.atr14)) snap.valid = false;
   if(!CopyLatestValue(g_handleObv, snap.obv))     snap.valid = false;

   if(!ComputeSupportResistance(symbol, g_msTimeframe, MS_SR_LOOKBACK, snap.srSupport, snap.srResistance))
      snap.valid = false;

   if(!ComputePivotPoints(symbol, snap.pivotP, snap.pivotR1, snap.pivotR2, snap.pivotS1, snap.pivotS2))
      snap.valid = false;

   if(!ComputeFibonacci(symbol, g_msTimeframe, MS_FIBO_LOOKBACK, snap.fiboDirection,
                        snap.fiboSwingHigh, snap.fiboSwingLow, snap.fibo382, snap.fibo500, snap.fibo618))
      snap.valid = false;

   ComputeSmc(symbol, g_msTimeframe, snap); // best-effort, tidak menggagalkan valid kalau data kurang

   // Candle OHLC terakhir (untuk Price Action) -- index1..MS_CANDLE_COUNT, urut TERBARU dulu.
   double o[], h[], l[], c[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
   if(CopyOpen(symbol, g_msTimeframe, 1, MS_CANDLE_COUNT, o) != MS_CANDLE_COUNT ||
      CopyHigh(symbol, g_msTimeframe, 1, MS_CANDLE_COUNT, h) != MS_CANDLE_COUNT ||
      CopyLow(symbol, g_msTimeframe, 1, MS_CANDLE_COUNT, l) != MS_CANDLE_COUNT ||
      CopyClose(symbol, g_msTimeframe, 1, MS_CANDLE_COUNT, c) != MS_CANDLE_COUNT)
     {
      snap.valid = false;
     }
   else
     {
      for(int i = 0; i < MS_CANDLE_COUNT; i++)
        {
         snap.candleOpen[i]  = o[i];
         snap.candleHigh[i]  = h[i];
         snap.candleLow[i]   = l[i];
         snap.candleClose[i] = c[i];
        }
     }

   if(!CopyLatestValue(g_handleHtfEma20, snap.htfEma20))   snap.valid = false;
   if(!CopyLatestValue(g_handleHtfEma50, snap.htfEma50))   snap.valid = false;
   if(!CopyLatestValue(g_handleHtfEma200, snap.htfEma200)) snap.valid = false;
   double htfClose[];
   ArraySetAsSeries(htfClose, true);
   if(CopyClose(symbol, g_msHtfTimeframe, 1, 1, htfClose) == 1) snap.htfLastClose = htfClose[0];
   else snap.valid = false;

   return snap;
  }
//+------------------------------------------------------------------+
