//+------------------------------------------------------------------+
//|                                              DidinskaSignalEA.mq5 |
//|                                                                    |
//| FASE 1 -- KERANGKA + STATE MACHINE + 2 ANALIS (Trend & Momentum). |
//| Tujuan fase ini CUMA buat buktiin alur end-to-end jalan:           |
//|   ambil data native MQL5 -> panggil Anthropic 2x (Trend, Momentum)|
//|   -> kirim hasilnya ke Telegram.                                  |
//| BELUM ADA: analis lain (8 lagi), AI Penyimpul (penarik kesimpulan |
//| akhir), eksekusi order ke MT5, risk management, logging lokal.    |
//| Itu semua NYUSUL di fase berikutnya, dibangun di atas kerangka    |
//| yang sama ini.                                                    |
//|                                                                    |
//| SEBELUM DIJALANKAN:                                                |
//| 1. Compile di MetaEditor (F7) -- kalau ada error compile, kirim   |
//|    balik pesan errornya persis, saya perbaiki.                    |
//| 2. Tools > Options > Expert Advisors > centang "Allow WebRequest  |
//|    for listed URL", tambahkan PERSIS 2 URL ini:                  |
//|      https://api.anthropic.com                                    |
//|      https://api.telegram.org                                     |
//| 3. Isi Inp_AnthropicApiKey, Inp_TelegramBotToken, Inp_TelegramChatId|
//|    di tab Inputs sebelum attach ke chart.                          |
//| 4. Attach ke chart XAUUSD, centang "Allow Algo Trading".           |
//+------------------------------------------------------------------+
#property copyright "Didinska Signal"
#property version   "0.1"
#property strict

#include "AnthropicApi.mqh"
#include "TelegramApi.mqh"
#include "MarketSnapshot.mqh"
#include "Analysts.mqh"

//--- Input parameter (diisi user lewat tab "Inputs" di MT5) ----------
input string   Inp_AnthropicApiKey   = "";                  // Anthropic API Key
input string   Inp_AnthropicModel    = "claude-opus-5";      // Model Anthropic yang dipakai
input int      Inp_MaxTokensAnalyst  = 500;                  // Max token jawaban tiap analis
input string   Inp_TelegramBotToken  = "";                  // Token bot Telegram
input string   Inp_TelegramChatId    = "";                  // Chat ID tujuan notifikasi
input ENUM_TIMEFRAMES Inp_Timeframe  = PERIOD_M15;           // Timeframe utama analisa
input string   Inp_TradeModeLabel    = "daytrade";           // Label mode trading (buat prompt AI saja, fase ini)
input int      Inp_CycleIntervalSec  = 600;                  // Jeda antar siklus penuh (detik) -- 600 = 10 menit
input int      Inp_StepIntervalSec   = 3;                    // Jeda antar LANGKAH state machine (detik)
input int      Inp_WebRequestTimeoutMs = 20000;              // Timeout tiap panggilan API (ms)

//--- State machine ------------------------------------------------------
enum EaState
  {
   STATE_IDLE,             // nunggu siklus berikutnya
   STATE_GATHER_DATA,      // ambil MarketSnapshot
   STATE_CALL_TREND,       // panggil Anthropic buat analis Trend
   STATE_CALL_MOMENTUM,    // panggil Anthropic buat analis Momentum
   STATE_REPORT,           // kirim ringkasan ke Telegram
   STATE_WAIT_NEXT_CYCLE   // jeda sebelum mulai siklus berikutnya lagi
  };

EaState        g_state = STATE_IDLE;
datetime       g_nextStepTime = 0;
MarketSnapshot g_snapshot;
string         g_opinionTrend = "";
string         g_opinionMomentum = "";
string         g_symbol = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_symbol = _Symbol;

   if(Inp_AnthropicApiKey == "")
     {
      Print("[Init] Inp_AnthropicApiKey kosong -- isi dulu API key Anthropic di tab Inputs.");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(!MarketSnapshot_Init(g_symbol, Inp_Timeframe))
     {
      Print("[Init] Gagal inisialisasi indicator handle.");
      return INIT_FAILED;
     }

   EventSetTimer(Inp_StepIntervalSec);

   g_state = STATE_GATHER_DATA; // langsung mulai 1 siklus tes begitu EA nyala
   g_nextStepTime = TimeCurrent();

   Print("[Init] DidinskaSignalEA Fase 1 siap. Symbol=", g_symbol, " Timeframe=", EnumToString(Inp_Timeframe));
   TelegramSendMessage(Inp_TelegramBotToken, Inp_TelegramChatId,
                        "🟢 <b>DidinskaSignalEA Fase 1</b> mulai jalan di " + g_symbol + ".\nBaru ada 2 analis (Trend+Momentum) buat tes alur -- belum eksekusi order apa pun.");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   MarketSnapshot_Deinit();
  }

//+------------------------------------------------------------------+
//| Expert tick function -- SENGAJA DIKOSONGKAN. Semua logic jalan di |
//| OnTimer(), bukan di sini -- soalnya siklus analisa kita berbasis   |
//| WAKTU (tiap N menit), bukan tiap ada tick harga baru (yang buat    |
//| XAUUSD bisa BERKALI-KALI per detik, kalau logic taruh di sini bisa |
//| ke-trigger ratusan kali per detik).                                |
//+------------------------------------------------------------------+
void OnTick()
  {
  }

//+------------------------------------------------------------------+
//| Expert timer function -- JANTUNG state machine. Dipanggil tiap    |
//| Inp_StepIntervalSec detik, majuin state SATU LANGKAH tiap kali     |
//| dipanggil (BUKAN semua langkah sekaligus) -- ini yang mencegah    |
//| WebRequest yang blocking bikin terminal freeze lama.               |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(TimeCurrent() < g_nextStepTime)
      return; // belum waktunya lanjut ke langkah berikutnya

   switch(g_state)
     {
      case STATE_IDLE:
         // Tidak ada apa-apa buat dilakukan -- nunggu STATE_WAIT_NEXT_CYCLE
         // yang majuin ke STATE_GATHER_DATA lagi.
         break;

      case STATE_GATHER_DATA:
        {
         g_snapshot = MarketSnapshot_Get(g_symbol);
         if(!g_snapshot.valid)
           {
            Print("[State] Gagal ambil MarketSnapshot (history belum cukup?). Coba lagi siklus berikutnya.");
            g_state = STATE_WAIT_NEXT_CYCLE;
            g_nextStepTime = TimeCurrent() + Inp_CycleIntervalSec;
            break;
           }
         Print("[State] Snapshot OK. lastPrice=", g_snapshot.lastPrice, " ema20=", g_snapshot.ema20,
               " ema50=", g_snapshot.ema50, " ema200=", g_snapshot.ema200, " rsi14=", g_snapshot.rsi14);
         g_state = STATE_CALL_TREND;
         g_nextStepTime = TimeCurrent(); // lanjut langsung ke langkah berikutnya
         break;
        }

      case STATE_CALL_TREND:
        {
         string systemPrompt = BuildTrendSystemPrompt(g_symbol, Inp_TradeModeLabel);
         string dataJson     = BuildTrendDataJson(g_snapshot);
         string errText      = "";

         bool ok = AnthropicChatCall(Inp_AnthropicApiKey, Inp_AnthropicModel, Inp_MaxTokensAnalyst,
                                      systemPrompt, dataJson, Inp_WebRequestTimeoutMs,
                                      g_opinionTrend, errText);
         if(!ok)
           {
            Print("[Trend] GAGAL: ", errText);
            g_opinionTrend = "(gagal: " + errText + ")";
           }
         else
           {
            Print("[Trend] Opini: ", g_opinionTrend);
           }

         g_state = STATE_CALL_MOMENTUM;
         g_nextStepTime = TimeCurrent() + Inp_StepIntervalSec; // kasih jeda sebelum call berikutnya
         break;
        }

      case STATE_CALL_MOMENTUM:
        {
         string systemPrompt = BuildMomentumSystemPrompt(g_symbol, Inp_TradeModeLabel);
         string dataJson     = BuildMomentumDataJson(g_snapshot);
         string errText      = "";

         bool ok = AnthropicChatCall(Inp_AnthropicApiKey, Inp_AnthropicModel, Inp_MaxTokensAnalyst,
                                      systemPrompt, dataJson, Inp_WebRequestTimeoutMs,
                                      g_opinionMomentum, errText);
         if(!ok)
           {
            Print("[Momentum] GAGAL: ", errText);
            g_opinionMomentum = "(gagal: " + errText + ")";
           }
         else
           {
            Print("[Momentum] Opini: ", g_opinionMomentum);
           }

         g_state = STATE_REPORT;
         g_nextStepTime = TimeCurrent();
         break;
        }

      case STATE_REPORT:
        {
         string biasTrend    = ExtractBiasFromOpinion(g_opinionTrend);
         string biasMomentum = ExtractBiasFromOpinion(g_opinionMomentum);

         string msg = "📊 <b>Tes Fase 1 -- " + g_symbol + "</b>\n\n";
         msg += "Harga: " + DoubleToString(g_snapshot.lastPrice, 2) + "\n\n";
         msg += "🧭 <b>Trend</b> (Bias: " + biasTrend + ")\n" + g_opinionTrend + "\n\n";
         msg += "📈 <b>Momentum</b> (Bias: " + biasMomentum + ")\n" + g_opinionMomentum;

         TelegramSendMessage(Inp_TelegramBotToken, Inp_TelegramChatId, msg);
         Print("[State] Laporan tes terkirim ke Telegram.");

         g_state = STATE_WAIT_NEXT_CYCLE;
         g_nextStepTime = TimeCurrent() + Inp_CycleIntervalSec;
         break;
        }

      case STATE_WAIT_NEXT_CYCLE:
         g_state = STATE_GATHER_DATA;
         g_nextStepTime = TimeCurrent();
         break;
     }
  }
//+------------------------------------------------------------------+
