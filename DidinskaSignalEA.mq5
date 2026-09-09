//+------------------------------------------------------------------+
//|                                              DidinskaSignalEA.mq5 |
//|                                                                    |
//| FASE 2 -- 10 analis spesialis + 1 AI Penyimpul (11 pemanggilan AI  |
//| per siklus), masing-masing bisa pakai API key TERPISAH (11 slot   |
//| input) supaya tidak saling kena rate limit -- port dari strategi  |
//| "Konfluensi 3 Pilar" di Didinska Signal Bot (Cloudflare Workers).  |
//|                                                                    |
//| BELUM ADA (nyusul di fase berikutnya): eksekusi order ke MT5,      |
//| logging riwayat sinyal lokal, guardrail risiko harian/max trade.   |
//| Fase ini FOKUS ke kualitas ANALISA & SINYAL dulu -- eksekusi baru  |
//| aman ditambah setelah sinyal teksnya terbukti jalan stabil.        |
//|                                                                    |
//| SEBELUM DIJALANKAN:                                                |
//| 1. Compile di MetaEditor (F7) -- kalau ada error compile, kirim   |
//|    balik pesan errornya persis, saya perbaiki.                    |
//| 2. Tools > Options > Expert Advisors > centang "Allow WebRequest  |
//|    for listed URL", tambahkan PERSIS:                              |
//|      https://api.groq.com       (default -- provider AI live)    |
//|      https://api.telegram.org   (notifikasi)                     |
//|      https://api.anthropic.com  (HANYA kalau Inp_UseAnthropic=true)|
//| 3. Isi minimal Inp_OpenAiApiKey (fallback bersama) ATAU isi SEMUA  |
//|    11 slot Inp_ApiKey_1..10 + Inp_ApiKey_Summarizer satu-satu --   |
//|    salah satu dari dua opsi ini WAJIB dipenuhi. Kalau isi 11 slot  |
//|    lengkap, field fallback boleh dikosongkan.                     |
//| 4. Attach ke chart, centang "Allow Algo Trading".                  |
//|                                                                    |
//| FIX (2026-09-09): validasi OnInit() dulu WAJIB Inp_OpenAiApiKey    |
//| (fallback) terisi meskipun 11 slot individual sudah lengkap --     |
//| sekarang fallback jadi opsional selama semua 11 slot terisi.       |
//|                                                                    |
//| FIX v2.02 (2026-09-09): bug ArrayResize(postData, bodyLen-1) yang  |
//| memotong byte '}' penutup JSON (sebelumnya cuma dibenerin di       |
//| OpenAiCompatibleApi.mqh) ternyata MASIH ADA juga di                |
//| AnthropicApi.mqh dan ketiga fungsi di TelegramApi.mqh -- semua     |
//| sudah dihapus. Kalau Inp_UseAnthropic=true, atau notifikasi        |
//| Telegram sebelumnya gagal terus, ini penyebabnya.                  |
//+------------------------------------------------------------------+
#property copyright "Didinska Signal"
#property version   "2.02"
#property strict

#include "AnthropicApi.mqh"
#include "OpenAiCompatibleApi.mqh"
#include "TelegramApi.mqh"
#include "MarketSnapshot.mqh"
#include "Analysts.mqh"
#include "Summarizer.mqh"

//--- Provider AI --------------------------------------------------------
input bool     Inp_UseAnthropic      = false;                // true = pakai Anthropic (berbayar); false = pakai Groq (default)

//--- Dipakai HANYA kalau Inp_UseAnthropic = true -------------------------
input string   Inp_AnthropicApiKey   = "";                  // Anthropic API Key (FALLBACK kalau slot 1-11 di bawah kosong)
input string   Inp_AnthropicModel    = "claude-opus-5";      // Model Anthropic (dipakai analis MAUPUN Penyimpul)

//--- Dipakai HANYA kalau Inp_UseAnthropic = false ------------------------
input string   Inp_OpenAiBaseUrl        = "https://api.groq.com/openai/v1/chat/completions"; // Endpoint chat-completions
input string   Inp_OpenAiApiKey         = "";                  // Groq API Key (FALLBACK kalau slot 1-11 di bawah kosong)
input string   Inp_OpenAiModel          = "llama-3.3-70b-versatile"; // Model buat 10 analis
input string   Inp_OpenAiSummaryModel   = "openai/gpt-oss-120b";     // Model buat AI Penyimpul (boleh beda dari analis)

//--- 11 API KEY TERPISAH (opsional per-slot) -----------------------------
// Kosongkan slot mana pun buat fallback ke Inp_OpenAiApiKey/Inp_AnthropicApiKey
// di atas. Isi SEMUA 11 slot dengan key/akun BERBEDA kalau mau tiap
// panggilan AI pakai kuota sendiri-sendiri (paling efektif hindari 429).
input string   Inp_ApiKey_1  = ""; // Key AI 1 - Trend
input string   Inp_ApiKey_2  = ""; // Key AI 2 - Momentum
input string   Inp_ApiKey_3  = ""; // Key AI 3 - Volatilitas
input string   Inp_ApiKey_4  = ""; // Key AI 4 - Volume
input string   Inp_ApiKey_5  = ""; // Key AI 5 - Support & Resistance
input string   Inp_ApiKey_6  = ""; // Key AI 6 - Smart Money Concepts
input string   Inp_ApiKey_7  = ""; // Key AI 7 - Price Action
input string   Inp_ApiKey_8  = ""; // Key AI 8 - Multi-Timeframe
input string   Inp_ApiKey_9  = ""; // Key AI 9 - Konteks Makro
input string   Inp_ApiKey_10 = ""; // Key AI 10 - Risk Management
input string   Inp_ApiKey_Summarizer = ""; // Key AI ke-11 - Penyimpul

//--- Input umum -----------------------------------------------------------
input int      Inp_MaxTokensAnalyst    = 500;                 // Max token jawaban tiap analis
input int      Inp_MaxTokensSummarizer = 1200;                // Max token jawaban Penyimpul
input string   Inp_TelegramBotToken    = "";                  // Token bot Telegram
input string   Inp_TelegramChatId      = "";                  // Chat ID tujuan notifikasi
input ENUM_TIMEFRAMES Inp_Timeframe    = PERIOD_M15;           // Timeframe utama analisa
input ENUM_TIMEFRAMES Inp_HtfTimeframe = PERIOD_H1;            // Timeframe besar (buat analis MTF)
input string   Inp_TradeModeLabel      = "daytrade";           // Label mode trading (buat prompt AI)
input int      Inp_CycleIntervalSec    = 600;                  // Jeda antar siklus penuh (detik) -- 600 = 10 menit
input int      Inp_StepIntervalSec     = 3;                    // Jeda antar LANGKAH state machine (detik)
input int      Inp_WebRequestTimeoutMs = 20000;                // Timeout tiap panggilan API (ms)

//--- State machine ---------------------------------------------------------
enum EaState
  {
   STATE_IDLE,
   STATE_GATHER_DATA,     // ambil MarketSnapshot + mulai pesan progres Telegram
   STATE_CALL_ANALYST,    // panggil AI ke-(g_analystIndex+1), loop 10x
   STATE_CALL_SUMMARIZER, // panggil AI Penyimpul (AI ke-11)
   STATE_REPORT,          // finalisasi & edit pesan Telegram jadi hasil akhir
   STATE_WAIT_NEXT_CYCLE
  };

EaState        g_state = STATE_IDLE;
datetime       g_nextStepTime = 0;
MarketSnapshot g_snapshot;
string         g_symbol = "";
int            g_analystIndex = 0; // 0..ANALYST_COUNT-1
string         g_opinionText[ANALYST_COUNT];
string         g_opinionBias[ANALYST_COUNT];
long           g_progressMsgId = -1;
string         g_finalSignalText = "";

//+------------------------------------------------------------------+
//| Ambil API key khusus untuk 1 nomor analis (1-10). Fallback ke key  |
//| bersama (Groq/Anthropic sesuai provider aktif) kalau slotnya       |
//| kosong -- SAMA polanya dengan getAnalystApiKey() di groqClient.js. |
//+------------------------------------------------------------------+
string GetApiKeyForAnalyst(const int number)
  {
   string dedicated = "";
   switch(number)
     {
      case 1:  dedicated = Inp_ApiKey_1;  break;
      case 2:  dedicated = Inp_ApiKey_2;  break;
      case 3:  dedicated = Inp_ApiKey_3;  break;
      case 4:  dedicated = Inp_ApiKey_4;  break;
      case 5:  dedicated = Inp_ApiKey_5;  break;
      case 6:  dedicated = Inp_ApiKey_6;  break;
      case 7:  dedicated = Inp_ApiKey_7;  break;
      case 8:  dedicated = Inp_ApiKey_8;  break;
      case 9:  dedicated = Inp_ApiKey_9;  break;
      case 10: dedicated = Inp_ApiKey_10; break;
     }
   if(dedicated != "") return dedicated;
   return Inp_UseAnthropic ? Inp_AnthropicApiKey : Inp_OpenAiApiKey;
  }

string GetApiKeyForSummarizer()
  {
   if(Inp_ApiKey_Summarizer != "") return Inp_ApiKey_Summarizer;
   return Inp_UseAnthropic ? Inp_AnthropicApiKey : Inp_OpenAiApiKey;
  }

//+------------------------------------------------------------------+
//| Titik tunggal buat panggil AI -- otomatis pilih Anthropic atau     |
//| provider universal sesuai Inp_UseAnthropic. apiKey & model         |
//| diteruskan sebagai parameter (BUKAN input global) supaya tiap      |
//| analis/Penyimpul bisa pakai key & model berbeda-beda.              |
//+------------------------------------------------------------------+
bool CallAi(const string apiKey, const string model, const int maxTokens,
            const string systemPrompt, const string userContent, string &outText, string &outError)
  {
   if(Inp_UseAnthropic)
      return AnthropicChatCall(apiKey, model, maxTokens, systemPrompt, userContent,
                                Inp_WebRequestTimeoutMs, outText, outError);

   return OpenAiCompatibleChatCall(Inp_OpenAiBaseUrl, apiKey, model, maxTokens,
                                    systemPrompt, userContent, Inp_WebRequestTimeoutMs, outText, outError);
  }

//+------------------------------------------------------------------+
//| Router system prompt & data JSON per nomor analis (1-10) -- 1      |
//| tempat tunggal biar STATE_CALL_ANALYST tidak perlu 10 blok kode    |
//| terpisah.                                                          |
//+------------------------------------------------------------------+
string BuildAnalystSystemPrompt(const int number, const string symbol, const string tradeMode)
  {
   switch(number)
     {
      case 1:  return BuildTrendSystemPrompt(symbol, tradeMode);
      case 2:  return BuildMomentumSystemPrompt(symbol, tradeMode);
      case 3:  return BuildVolatilitySystemPrompt(symbol, tradeMode);
      case 4:  return BuildVolumeSystemPrompt(symbol, tradeMode);
      case 5:  return BuildSrSystemPrompt(symbol, tradeMode);
      case 6:  return BuildSmcSystemPrompt(symbol, tradeMode);
      case 7:  return BuildPriceActionSystemPrompt(symbol, tradeMode);
      case 8:  return BuildMtfSystemPrompt(symbol, tradeMode);
      case 9:  return BuildMacroSystemPrompt(symbol, tradeMode);
      case 10: return BuildRiskSystemPrompt(symbol, tradeMode);
     }
   return "";
  }

string BuildAnalystDataJson(const int number, const MarketSnapshot &snap, const string tradeMode)
  {
   switch(number)
     {
      case 1:  return BuildTrendDataJson(snap);
      case 2:  return BuildMomentumDataJson(snap);
      case 3:  return BuildVolatilityDataJson(snap);
      case 4:  return BuildVolumeDataJson(snap);
      case 5:  return BuildSrDataJson(snap);
      case 6:  return BuildSmcDataJson(snap);
      case 7:  return BuildPriceActionDataJson(snap);
      case 8:  return BuildMtfDataJson(snap, EnumToString(Inp_Timeframe), EnumToString(Inp_HtfTimeframe));
      case 9:  return BuildMacroDataJson(snap);
      case 10: return BuildRiskDataJson(snap, tradeMode);
     }
   return "{}";
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_symbol = _Symbol;

   if(Inp_UseAnthropic)
     {
      // Anthropic: cukup 1 key fallback (belum ada skema 11 slot terpisah
      // untuk Anthropic di versi ini), jadi tetap wajib diisi.
      if(Inp_AnthropicApiKey == "")
        {
         Print("[Init] Inp_UseAnthropic=true tapi Inp_AnthropicApiKey (fallback) kosong.");
         return INIT_PARAMETERS_INCORRECT;
        }
     }
   else
     {
      if(Inp_OpenAiBaseUrl == "")
        {
         Print("[Init] Inp_OpenAiBaseUrl kosong -- endpoint chat-completions wajib diisi.");
         return INIT_PARAMETERS_INCORRECT;
        }

      // Fallback (Inp_OpenAiApiKey) HANYA wajib diisi kalau ADA slot
      // individual (Inp_ApiKey_1..10 / Inp_ApiKey_Summarizer) yang masih
      // kosong -- karena slot kosong itu bakal jatuh ke fallback saat
      // dipanggil (lihat GetApiKeyForAnalyst/GetApiKeyForSummarizer).
      // Kalau semua 11 slot sudah lengkap, fallback boleh dikosongkan.
      bool semuaSlotTerisi = (Inp_ApiKey_1 != "" && Inp_ApiKey_2 != "" && Inp_ApiKey_3 != "" &&
                              Inp_ApiKey_4 != "" && Inp_ApiKey_5 != "" && Inp_ApiKey_6 != "" &&
                              Inp_ApiKey_7 != "" && Inp_ApiKey_8 != "" && Inp_ApiKey_9 != "" &&
                              Inp_ApiKey_10 != "" && Inp_ApiKey_Summarizer != "");

      if(Inp_OpenAiApiKey == "" && !semuaSlotTerisi)
        {
         Print("[Init] Inp_UseAnthropic=false, Inp_OpenAiApiKey (fallback) kosong, dan masih ada slot Inp_ApiKey_1..10/Inp_ApiKey_Summarizer yang kosong. Isi salah satu: fallback ATAU lengkapi semua 11 slot.");
         return INIT_PARAMETERS_INCORRECT;
        }
     }

   if(!MarketSnapshot_Init(g_symbol, Inp_Timeframe, Inp_HtfTimeframe))
     {
      Print("[Init] Gagal inisialisasi indicator handle.");
      return INIT_FAILED;
     }

   EventSetTimer(Inp_StepIntervalSec);

   g_state = STATE_GATHER_DATA;
   g_nextStepTime = TimeCurrent();

   string modelLabel = Inp_UseAnthropic ? ("Anthropic:" + Inp_AnthropicModel) : (Inp_OpenAiModel + " (Penyimpul: " + Inp_OpenAiSummaryModel + ")");
   Print("[Init] DidinskaSignalEA Fase 2 siap. Symbol=", g_symbol, " TF=", EnumToString(Inp_Timeframe),
         " HTF=", EnumToString(Inp_HtfTimeframe), " Provider=", modelLabel);

   TelegramSendMessage(Inp_TelegramBotToken, Inp_TelegramChatId,
                        "🟢 <b>DidinskaSignalEA Fase 2</b> mulai jalan di " + g_symbol +
                        ".\n10 analis spesialis + 1 AI Penyimpul (strategi \"Konfluensi 3 Pilar\") aktif.\n" +
                        "Siklus tiap " + IntegerToString(Inp_CycleIntervalSec / 60) + " menit. Belum ada eksekusi order otomatis di fase ini.");

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
//| Sengaja dikosongkan -- semua logic jalan di OnTimer() (siklus      |
//| berbasis waktu, bukan tiap tick).                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
  }

//+------------------------------------------------------------------+
//| Jantung state machine. Majuin 1 langkah tiap Inp_StepIntervalSec.  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(TimeCurrent() < g_nextStepTime)
      return;

   switch(g_state)
     {
      case STATE_IDLE:
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
         Print("[State] Snapshot OK. lastPrice=", g_snapshot.lastPrice);

         g_analystIndex = 0;
         for(int i = 0; i < ANALYST_COUNT; i++) { g_opinionText[i] = ""; g_opinionBias[i] = "Netral"; }

         g_progressMsgId = -1;
         TelegramSendMessageEx(Inp_TelegramBotToken, Inp_TelegramChatId,
                                "🤖 AI 1/" + IntegerToString(ANALYST_COUNT) + " — <b>" + AnalystTitle(1) + "</b> sedang menganalisa...",
                                g_progressMsgId);

         g_state = STATE_CALL_ANALYST;
         g_nextStepTime = TimeCurrent();
         break;
        }

      case STATE_CALL_ANALYST:
        {
         int number = g_analystIndex + 1;
         string systemPrompt = BuildAnalystSystemPrompt(number, g_symbol, Inp_TradeModeLabel);
         string dataJson     = BuildAnalystDataJson(number, g_snapshot, Inp_TradeModeLabel);
         string apiKey       = GetApiKeyForAnalyst(number);
         string model        = Inp_UseAnthropic ? Inp_AnthropicModel : Inp_OpenAiModel;
         string outText = "", outError = "";

         bool ok = CallAi(apiKey, model, Inp_MaxTokensAnalyst, systemPrompt, dataJson, outText, outError);
         if(!ok)
           {
            Print("[AI ", number, "] GAGAL: ", outError);
            outText = "(gagal mengambil opini: " + outError + ")";
           }
         else
           {
            Print("[AI ", number, "] Opini: ", outText);
           }

         g_opinionText[g_analystIndex] = outText;
         g_opinionBias[g_analystIndex] = ExtractBiasFromOpinion(outText);

         string preview = outText;
         if(StringLen(preview) > 220) preview = StringSubstr(preview, 0, 220) + "...";
         string progressMsg = "✅ AI " + IntegerToString(number) + "/" + IntegerToString(ANALYST_COUNT) +
                               " — <b>" + AnalystTitle(number) + "</b> selesai (Bias: " + g_opinionBias[g_analystIndex] + "):\n\n" +
                               EscapeHtml(preview);
         TelegramEditMessage(Inp_TelegramBotToken, Inp_TelegramChatId, g_progressMsgId, progressMsg);

         g_analystIndex++;
         if(g_analystIndex >= ANALYST_COUNT)
           {
            g_state = STATE_CALL_SUMMARIZER;
            g_nextStepTime = TimeCurrent() + Inp_StepIntervalSec;
           }
         else
           {
            TelegramEditMessage(Inp_TelegramBotToken, Inp_TelegramChatId, g_progressMsgId,
                                 progressMsg + "\n\n🤖 AI " + IntegerToString(g_analystIndex + 1) + "/" + IntegerToString(ANALYST_COUNT) +
                                 " — <b>" + AnalystTitle(g_analystIndex + 1) + "</b> sedang menganalisa...");
            g_state = STATE_CALL_ANALYST;
            g_nextStepTime = TimeCurrent() + Inp_StepIntervalSec;
           }
         break;
        }

      case STATE_CALL_SUMMARIZER:
        {
         TelegramEditMessage(Inp_TelegramBotToken, Inp_TelegramChatId, g_progressMsgId,
                              "🧠 AI Penyimpul sedang merangkum " + IntegerToString(ANALYST_COUNT) + " hasil analisa jadi 1 keputusan final...");

         int bullish, bearish, netral;
         TallyBias(g_opinionBias, ANALYST_COUNT, bullish, bearish, netral);

         string trendBias, levelBias, momentumBias, dominant;
         int alignedCount;
         ComputePillarAlignment(g_opinionBias, trendBias, levelBias, momentumBias, alignedCount, dominant);

         string systemPrompt = BuildSummarizerSystemPrompt(ANALYST_COUNT, g_symbol, Inp_TradeModeLabel,
                                                            bullish, bearish, netral, alignedCount, dominant,
                                                            trendBias, levelBias, momentumBias);

         string opinionsText = "";
         for(int i = 0; i < ANALYST_COUNT; i++)
           {
            opinionsText += "AI " + IntegerToString(i + 1) + " (" + AnalystTitle(i + 1) + "):\n" + g_opinionText[i];
            if(i < ANALYST_COUNT - 1) opinionsText += "\n\n";
           }

         string apiKey = GetApiKeyForSummarizer();
         string model  = Inp_UseAnthropic ? Inp_AnthropicModel : Inp_OpenAiSummaryModel;
         string outText = "", outError = "";

         bool ok = CallAi(apiKey, model, Inp_MaxTokensSummarizer, systemPrompt, opinionsText, outText, outError);
         if(!ok)
           {
            Print("[Penyimpul] GAGAL: ", outError);
            g_finalSignalText = "🎯 Keputusan: WAIT\n⚠️ AI Penyimpul gagal merespons: " + outError;
           }
         else
           {
            Print("[Penyimpul] Hasil: ", outText);
            g_finalSignalText = outText;
           }

         g_state = STATE_REPORT;
         g_nextStepTime = TimeCurrent();
         break;
        }

      case STATE_REPORT:
        {
         string decision = DetectDecision(g_finalSignalText);
         double entry = -1, sl = -1, tp = -1;
         if(decision == "BUY" || decision == "SELL")
           {
            entry = ExtractPriceAfterLabel(g_finalSignalText, "Skenario Entry", g_snapshot.lastPrice);
            sl    = ExtractPriceAfterLabel(g_finalSignalText, "Stop-Loss", g_snapshot.lastPrice);
            tp    = ExtractPriceAfterLabel(g_finalSignalText, "Take-Profit", g_snapshot.lastPrice);
           }

         int bullish, bearish, netral;
         TallyBias(g_opinionBias, ANALYST_COUNT, bullish, bearish, netral);
         string trendBias, levelBias, momentumBias, dominant;
         int alignedCount;
         ComputePillarAlignment(g_opinionBias, trendBias, levelBias, momentumBias, alignedCount, dominant);

         string codeBlock = BuildSignalCodeBlock(g_symbol, decision, entry, sl, tp, alignedCount, dominant);
         string tallyFooter = StringFormat("\n\n📊 Tally: %d Bullish, %d Bearish, %d Netral dari %d AI spesialis.",
                                            bullish, bearish, netral, ANALYST_COUNT);

         string finalMessage = "";
         if(codeBlock != "") finalMessage += codeBlock + "\n";
         finalMessage += EscapeHtml(g_finalSignalText) + tallyFooter;

         bool edited = TelegramEditMessage(Inp_TelegramBotToken, Inp_TelegramChatId, g_progressMsgId, finalMessage);
         if(!edited)
            TelegramSendMessage(Inp_TelegramBotToken, Inp_TelegramChatId, finalMessage);

         Print("[State] Laporan final terkirim. Decision=", decision, " Entry=", entry, " SL=", sl, " TP=", tp,
               " PilarSearah=", alignedCount, "/3 (", dominant, ")");

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
