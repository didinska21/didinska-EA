//+------------------------------------------------------------------+
//|                                              XAUUSD_EA.mq5       |
//|                       Phase 1 MVP - Trend Pullback System         |
//|                                  Version: 1.00                   |
//+------------------------------------------------------------------+
#property copyright "XAUUSD EA Pro"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_DIR
{
   DIR_NONE = 0,
   DIR_BUY  = 1,
   DIR_SELL = -1
};

enum ENUM_ENTRY_TYPE
{
   ENTRY_MARKET,
   ENTRY_LIMIT,
   ENTRY_STOP
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "════════ RISK MANAGEMENT ════════"
input double   InpRiskPercent       = 1.0;       // Risk per trade (% equity)
input double   InpMaxDailyLoss      = 3.0;       // Max daily loss (%)
input double   InpMaxTotalDD        = 15.0;      // Max total drawdown (%)
input int      InpMaxPositions      = 2;         // Max concurrent positions
input double   InpMaxSpreadPoints   = 50;        // Max spread (points, 5 pips)
input double   InpMinRR             = 1.5;       // Min Risk:Reward

input group "════════ MTF CONFIGURATION ════════"
input ENUM_TIMEFRAMES InpHTF_Trend   = PERIOD_H4;
input ENUM_TIMEFRAMES InpMTF_Logic   = PERIOD_H1;
input ENUM_TIMEFRAMES InpLTF_Entry   = PERIOD_M15;

input group "════════ INDICATOR SETTINGS ════════"
input int      InpEmaHTF            = 50;        // EMA H4
input int      InpEmaFast           = 21;        // EMA H1 fast
input int      InpEmaSlow           = 50;        // EMA H1 slow
input int      InpAdxPeriod         = 14;
input double   InpAdxMinTrend       = 25.0;      // ADX threshold for trend
input int      InpRsiMTF            = 14;        // RSI H1
input int      InpRsiLTF            = 7;         // RSI M15
input int      InpEmaLTF            = 9;         // EMA M15 micro
input int      InpAtrPeriod         = 14;

input group "════════ SESSION FILTER (server hours) ════════"
input bool     InpUseSession        = true;
input int      InpLondonStart       = 8;
input int      InpLondonEnd         = 12;
input int      InpNYStart           = 13;
input int      InpNYEnd             = 17;
input bool     InpTradeAsia         = false;

input group "════════ NEWS SHOCK PROTECTION ════════"
input bool     InpNewsShockMode     = true;      // Enable anti-shock mode
input int      InpNewsCooldownMins  = 30;        // Pause X mins after shock
input double   InpAtrShockMult      = 2.5;       // ATR multiplier to detect shock
input int      InpShockLookback     = 5;         // Candles to measure shock
input int      InpMaxSlippage       = 50;        // Max slippage points

input group "════════ TRADE MANAGEMENT ════════"
input bool     InpUseBreakeven      = true;
input double   InpBreakevenRR       = 1.0;       // Move to BE at 1R profit
input int      InpBreakevenPlusPts  = 2;         // BE + buffer (points)
input bool     InpUseTrailing       = true;
input double   InpTrailAtrMult      = 2.0;       // Trail distance = ATR x mult
input bool     InpUsePartialTP      = true;
input double   InpTP1RR             = 1.0;       // Close 50% at 1R
input double   InpTP2RR             = 2.0;       // Close 30% at 2R

input group "════════ VISUAL & ALERTS ════════"
input bool     InpShowDashboard     = true;
input bool     InpEnableAlerts      = true;
input bool     InpAlertPush         = false;     // Push notification

input group "════════ MAGIC NUMBERS ════════"
input int      InpMagicBase         = 10000;
input int      InpMagicTrend        = 10001;
input int      InpMagicRev          = 10002;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CAccountInfo   accInfo;
CSymbolInfo    symInfo;

int            g_handleEmaHTF   = INVALID_HANDLE;
int            g_handleEmaFast  = INVALID_HANDLE;
int            g_handleEmaSlow  = INVALID_HANDLE;
int            g_handleAdx      = INVALID_HANDLE;
int            g_handleRsiMTF   = INVALID_HANDLE;
int            g_handleRsiLTF   = INVALID_HANDLE;
int            g_handleEmaLTF   = INVALID_HANDLE;
int            g_handleAtrHTF   = INVALID_HANDLE;
int            g_handleAtrMTF   = INVALID_HANDLE;
int            g_handleAtrLTF   = INVALID_HANDLE;
int            g_handleBbMTF    = INVALID_HANDLE;

datetime       g_lastBarTime    = 0;
double         g_dayStartEquity = 0;
double         g_peakEquity     = 0;
datetime       g_lastTradeTime  = 0;
datetime       g_newsCooldownUntil = 0;
bool           g_isNewsCooldown = false;
int            g_shockCount     = 0;

// Dashboard
string         g_dashPrefix     = "XAU_EA_";

//+------------------------------------------------------------------+
//| INITIALIZATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Symbol info
   if(!symInfo.Name(_Symbol))
   {
      Print("❌ Failed to set symbol: ", _Symbol);
      return INIT_FAILED;
   }
   symInfo.Refresh();
   
   // Validate broker (5-digit check)
   if(symInfo.Point() == 0.00001) // 0.00001 = 5-digit forex, XAU should be 0.01
   {
      Print("⚠️ Warning: This EA designed for XAUUSD (point=0.01)");
   }
   
   // Init indicators
   g_handleEmaHTF  = iMA(_Symbol, InpHTF_Trend, InpEmaHTF, 0, MODE_EMA, PRICE_CLOSE);
   g_handleEmaFast = iMA(_Symbol, InpMTF_Logic, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_handleEmaSlow = iMA(_Symbol, InpMTF_Logic, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_handleAdx     = iADX(_Symbol, InpMTF_Logic, InpAdxPeriod);
   g_handleRsiMTF  = iRSI(_Symbol, InpMTF_Logic, InpRsiMTF, PRICE_CLOSE);
   g_handleRsiLTF  = iRSI(_Symbol, InpLTF_Entry, InpRsiLTF, PRICE_CLOSE);
   g_handleEmaLTF  = iMA(_Symbol, InpLTF_Entry, InpEmaLTF, 0, MODE_EMA, PRICE_CLOSE);
   g_handleAtrHTF  = iATR(_Symbol, InpHTF_Trend, InpAtrPeriod);
   g_handleAtrMTF  = iATR(_Symbol, InpMTF_Logic, InpAtrPeriod);
   g_handleAtrLTF  = iATR(_Symbol, InpLTF_Entry, InpAtrPeriod);
   g_handleBbMTF   = iBands(_Symbol, InpMTF_Logic, 20, 0, 2.0, PRICE_CLOSE);
   
   // Validate all handles
   if(g_handleEmaHTF  == INVALID_HANDLE || g_handleEmaFast == INVALID_HANDLE ||
      g_handleEmaSlow == INVALID_HANDLE || g_handleAdx    == INVALID_HANDLE ||
      g_handleRsiMTF  == INVALID_HANDLE || g_handleRsiLTF == INVALID_HANDLE ||
      g_handleEmaLTF  == INVALID_HANDLE || g_handleAtrHTF == INVALID_HANDLE ||
      g_handleAtrMTF  == INVALID_HANDLE || g_handleAtrLTF == INVALID_HANDLE ||
      g_handleBbMTF   == INVALID_HANDLE)
   {
      Print("❌ Failed to create indicator handles");
      return INIT_FAILED;
   }
   
   // Trade setup
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetTypeFilling(GetFillingType());
   trade.SetMarginMode();
   
   // Initial equity
   g_dayStartEquity = accInfo.Equity();
   g_peakEquity     = accInfo.Equity();
   
   // Dashboard
   if(InpShowDashboard) CreateDashboard();
   
   Print("═══════════════════════════════════════════");
   Print("✅ XAUUSD EA MVP v1.00 Initialized");
   Print("📊 Account: ", accInfo.Login(), " | Balance: $", DoubleToString(accInfo.Balance(), 2));
   Print("📊 Equity:  $", DoubleToString(accInfo.Equity(), 2));
   Print("⚙️ Risk/Trade: ", InpRiskPercent, "% | Max DD: ", InpMaxTotalDD, "%");
   Print("═══════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release handles
   if(g_handleEmaHTF  != INVALID_HANDLE) IndicatorRelease(g_handleEmaHTF);
   if(g_handleEmaFast != INVALID_HANDLE) IndicatorRelease(g_handleEmaFast);
   if(g_handleEmaSlow != INVALID_HANDLE) IndicatorRelease(g_handleEmaSlow);
   if(g_handleAdx     != INVALID_HANDLE) IndicatorRelease(g_handleAdx);
   if(g_handleRsiMTF  != INVALID_HANDLE) IndicatorRelease(g_handleRsiMTF);
   if(g_handleRsiLTF  != INVALID_HANDLE) IndicatorRelease(g_handleRsiLTF);
   if(g_handleEmaLTF  != INVALID_HANDLE) IndicatorRelease(g_handleEmaLTF);
   if(g_handleAtrHTF  != INVALID_HANDLE) IndicatorRelease(g_handleAtrHTF);
   if(g_handleAtrMTF  != INVALID_HANDLE) IndicatorRelease(g_handleAtrMTF);
   if(g_handleAtrLTF  != INVALID_HANDLE) IndicatorRelease(g_handleAtrLTF);
   if(g_handleBbMTF   != INVALID_HANDLE) IndicatorRelease(g_handleBbMTF);
   
   // Remove dashboard
   ObjectsDeleteAll(0, g_dashPrefix);
   
   Print("EA Removed | Reason: ", reason);
}

//+------------------------------------------------------------------+
//| MAIN TICK FUNCTION                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Refresh symbol info
   symInfo.Refresh();
   symInfo.RefreshRates();
   
   // Track peak equity
   if(accInfo.Equity() > g_peakEquity) g_peakEquity = accInfo.Equity();
   
   // Reset daily equity at new day
   MqlDateTime tmNow;
   TimeCurrent(tmNow);
   static int lastDay = -1;
   if(tmNow.day != lastDay)
   {
      g_dayStartEquity = accInfo.Equity();
      lastDay = tmNow.day;
   }
   
   //=== SAFETY CHECKS ===
   if(!CheckDailyDrawdown())
   {
      ManageOpenPositions();
      UpdateDashboard();
      return;
   }
   
   if(!CheckTotalDrawdown())
   {
      UpdateDashboard();
      return;
   }
   
   if(!CheckSpread())
   {
      ManageOpenPositions();
      UpdateDashboard();
      return;
   }
   
   //=== NEWS SHOCK DETECTION ===
   if(InpNewsShockMode)
   {
      DetectAndHandleShock();
   }
   
   if(g_isNewsCooldown)
   {
      ManageOpenPositions();
      UpdateDashboard();
      return;
   }
   
   //=== MANAGE OPEN POSITIONS ===
   ManageOpenPositions();
   
   //=== NEW BAR DETECTION ===
   datetime curBar = iTime(_Symbol, InpLTF_Entry, 0);
   bool isNewBar = (curBar != g_lastBarTime);
   
   //=== ENTRY SCAN (only on new bar) ===
   if(isNewBar && CountMyPositions() < InpMaxPositions)
   {
      ScanForEntry();
      g_lastBarTime = curBar;
   }
   
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| CHECK DAILY DRAWDOWN                                              |
//+------------------------------------------------------------------+
bool CheckDailyDrawdown()
{
   if(g_dayStartEquity <= 0) return true;
   
   double dd = (g_dayStartEquity - accInfo.Equity()) / g_dayStartEquity * 100.0;
   
   if(dd >= InpMaxDailyLoss)
   {
      static bool alerted = false;
      if(!alerted)
      {
         Print("🛑 DAILY DD LIMIT HIT: ", DoubleToString(dd, 2), "%");
         if(InpEnableAlerts) Alert("XAU EA: Daily DD Limit Hit!");
         alerted = true;
         CloseAllMyPositions();
      }
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| CHECK TOTAL DRAWDOWN                                              |
//+------------------------------------------------------------------+
bool CheckTotalDrawdown()
{
   if(g_peakEquity <= 0) return true;
   
   double dd = (g_peakEquity - accInfo.Equity()) / g_peakEquity * 100.0;
   
   if(dd >= InpMaxTotalDD)
   {
      static bool alerted = false;
      if(!alerted)
      {
         Print("🚨 TOTAL DD CIRCUIT BREAKER: ", DoubleToString(dd, 2), "%");
         if(InpEnableAlerts) Alert("XAU EA: TOTAL DD - EA PAUSED!");
         alerted = true;
         CloseAllMyPositions();
      }
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| CHECK SPREAD                                                      |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   long spread = symInfo.Spread();
   if(spread > (long)InpMaxSpreadPoints)
   {
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| NEWS SHOCK DETECTION & HANDLING                                   |
//+------------------------------------------------------------------+
void DetectAndHandleShock()
{
   // Get recent ATR
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_handleAtrLTF, 0, 1, InpShockLookback + 1, atr) < InpShockLookback + 1)
      return;
   
   // Calculate candle ranges
   bool shockDetected = false;
   double normalAtr = 0;
   
   // Average ATR
   for(int i = 2; i < InpShockLookback + 1; i++)
      normalAtr += atr[i];
   normalAtr /= InpShockLookback;
   
   // Check latest candle range
   double lastRange = iHigh(_Symbol, InpLTF_Entry, 1) - iLow(_Symbol, InpLTF_Entry, 1);
   
   // Shock = current range > 2.5x normal ATR
   if(lastRange > normalAtr * InpAtrShockMult)
   {
      shockDetected = true;
   }
   
   // Also detect price gap/jump
   double closePrev = iClose(_Symbol, InpLTF_Entry, 2);
   double closeLast = iClose(_Symbol, InpLTF_Entry, 1);
   double jump = MathAbs(closeLast - closePrev);
   
   if(jump > normalAtr * InpAtrShockMult)
      shockDetected = true;
   
   // Activate cooldown
   if(shockDetected && !g_isNewsCooldown)
   {
      g_shockCount++;
      g_isNewsCooldown = true;
      g_newsCooldownUntil = TimeCurrent() + InpNewsCooldownMins * 60;
      
      Print("⚡ NEWS SHOCK DETECTED! Cooldown ", InpNewsCooldownMins, " mins");
      Print("   Shock size: ", DoubleToString(lastRange / normalAtr, 2), "x normal ATR");
      
      // Reduce risk on existing positions
      // Move SL to breakeven for all positions
      ProtectPositionsFromShock();
      
      if(InpEnableAlerts)
      {
         Alert("XAU EA: News Shock Detected - Cooldown Active!");
         if(InpAlertPush)
            SendNotification("XAU EA: Shock detected, cooldown " + 
                             IntegerToString(InpNewsCooldownMins) + "min");
      }
   }
   
   // Check if cooldown ended
   if(g_isNewsCooldown && TimeCurrent() >= g_newsCooldownUntil)
   {
      g_isNewsCooldown = false;
      Print("✅ News cooldown ended, resuming normal trading");
      if(InpEnableAlerts)
         Alert("XAU EA: Cooldown ended, resuming");
   }
}

//+------------------------------------------------------------------+
//| PROTECT POSITIONS DURING SHOCK                                   |
//+------------------------------------------------------------------+
void ProtectPositionsFromShock()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(!IsMyMagic(posInfo.Magic())) continue;
      
      double openPrice = posInfo.PriceOpen();
      double curSl     = posInfo.StopLoss();
      
      // Move SL to breakeven + small buffer
      double newSl = NormalizeDouble(openPrice + symInfo.Point() * InpBreakevenPlusPts * 
                                     (posInfo.PositionType() == POSITION_TYPE_BUY ? 1 : -1), 
                                     (int)symInfo.Digits());
      
      bool slImproved = false;
      if(posInfo.PositionType() == POSITION_TYPE_BUY && newSl > curSl && curSl < openPrice)
         slImproved = true;
      if(posInfo.PositionType() == POSITION_TYPE_SELL && newSl < curSl && curSl > openPrice)
         slImproved = true;
      
      if(slImproved)
      {
         trade.PositionModify(posInfo.Ticket(), newSl, posInfo.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| SCAN FOR ENTRY SIGNALS                                            |
//+------------------------------------------------------------------+
void ScanForEntry()
{
   // Session filter
   if(InpUseSession && !IsActiveSession())
      return;
   
   // Minimum time between trades
   if(TimeCurrent() - g_lastTradeTime < PeriodSeconds(InpLTF_Entry))
      return;
   
   //=== GET H4 BIAS ===
   int h4Bias = GetHTFBias();
   if(h4Bias == 0) return; // neutral H4, skip
   
   //=== GET H1 ANALYSIS ===
   H1Analysis h1 = AnalyzeH1();
   
   // H1 must agree with H4
   if(h1.trend != h4Bias) return;
   
   // Need trending H1
   if(!h1.adxTrending) return;
   
   //=== GET M15 TRIGGER ===
   M15Signal m15 = GetM15Trigger(h1.trend, h1.zoneLow, h1.zoneHigh, h1.atr);
   
   if(m15.buySignal)
   {
      ExecuteBuy(m15.entryPrice, m15.sl, m15.tp);
   }
   else if(m15.sellSignal)
   {
      ExecuteSell(m15.entryPrice, m15.sl, m15.tp);
   }
}

//+------------------------------------------------------------------+
//| GET H4 BIAS                                                       |
//+------------------------------------------------------------------+
int GetHTFBias()
{
   double ema[];
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(g_handleEmaHTF, 0, 1, 3, ema) < 3) return 0;
   
   double close1 = iClose(_Symbol, InpHTF_Trend, 1);
   
   if(close1 > ema[1]) return +1;
   if(close1 < ema[1]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| H1 ANALYSIS STRUCTURE                                             |
//+------------------------------------------------------------------+
struct H1Analysis
{
   int    trend;
   double zoneLow;
   double zoneHigh;
   bool   adxTrending;
   double atr;
   double rsi;
};

H1Analysis AnalyzeH1()
{
   H1Analysis a = {0, 0, 0, false, 0, 0};
   
   double emaF[], emaS[], adxMain[], rsi[], atr[];
   ArraySetAsSeries(emaF, true); ArraySetAsSeries(emaS, true);
   ArraySetAsSeries(adxMain, true); ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(g_handleEmaFast, 0, 1, 5, emaF) < 5) return a;
   if(CopyBuffer(g_handleEmaSlow, 0, 1, 5, emaS) < 5) return a;
   if(CopyBuffer(g_handleAdx, 0, 1, 5, adxMain) < 5) return a;
   if(CopyBuffer(g_handleRsiMTF, 0, 1, 5, rsi) < 5) return a;
   if(CopyBuffer(g_handleAtrMTF, 0, 1, 5, atr) < 5) return a;
   
   a.atr = atr[1];
   a.rsi = rsi[1];
   a.adxTrending = (adxMain[1] > InpAdxMinTrend);
   
   // Trend: EMA21 > EMA50 stable
   if(emaF[1] > emaS[1] && emaF[2] > emaS[2] && emaF[3] > emaS[3])
      a.trend = +1;
   else if(emaF[1] < emaS[1] && emaF[2] < emaS[2] && emaF[3] < emaS[3])
      a.trend = -1;
   
   // Zone: last swing low/high in H1
   a.zoneLow  = iLow(_Symbol, InpMTF_Logic, 1);
   a.zoneHigh = iHigh(_Symbol, InpMTF_Logic, 1);
   
   return a;
}

//+------------------------------------------------------------------+
//| M15 SIGNAL STRUCTURE                                              |
//+------------------------------------------------------------------+
struct M15Signal
{
   bool   buySignal;
   bool   sellSignal;
   double entryPrice;
   double sl;
   double tp;
};

M15Signal GetM15Trigger(int h1Trend, double h1ZoneLow, double h1ZoneHigh, double h1Atr)
{
   M15Signal sig = {false, false, 0, 0, 0};
   
   double emaLTF[], rsiLTF[], bbUp[], bbDn[], atrLTF[];
   ArraySetAsSeries(emaLTF, true); ArraySetAsSeries(rsiLTF, true);
   ArraySetAsSeries(bbUp, true); ArraySetAsSeries(bbDn, true);
   ArraySetAsSeries(atrLTF, true);
   
   if(CopyBuffer(g_handleEmaLTF, 0, 1, 3, emaLTF) < 3) return sig;
   if(CopyBuffer(g_handleRsiLTF, 0, 1, 3, rsiLTF) < 3) return sig;
   if(CopyBuffer(g_handleBbMTF, 1, 1, 3, bbUp) < 3) return sig;  // upper
   if(CopyBuffer(g_handleBbMTF, 2, 1, 3, bbDn) < 3) return sig;  // lower
   if(CopyBuffer(g_handleAtrLTF, 0, 1, 3, atrLTF) < 3) return sig;
   
   double close1 = iClose(_Symbol, InpLTF_Entry, 1);
   double open1  = iOpen(_Symbol, InpLTF_Entry, 1);
   double high1  = iHigh(_Symbol, InpLTF_Entry, 1);
   double low1   = iLow(_Symbol, InpLTF_Entry, 1);
   
   bool   bullishCandle   = (close1 > open1);
   bool   bearishCandle   = (close1 < open1);
   double candleBody      = MathAbs(close1 - open1);
   bool   strongBullish   = bullishCandle && (candleBody > atrLTF[1] * 0.3) && (low1 < open1);
   bool   strongBearish   = bearishCandle && (candleBody > atrLTF[1] * 0.3) && (high1 > open1);
   bool   microUp         = (emaLTF[1] > emaLTF[2]);
   bool   microDown       = (emaLTF[1] < emaLTF[2]);
   
   //=== BUY TRIGGER ===
   if(h1Trend == +1)
   {
      bool inZone = (close1 <= h1ZoneLow + atrLTF[1] * 1.0);
      bool rsiReset = (rsiLTF[1] > 35 && rsiLTF[1] < 55);
      
      if(inZone && rsiReset && strongBullish && microUp)
      {
         sig.buySignal  = true;
         sig.entryPrice = close1;
         sig.sl         = NormalizeDouble(low1 - atrLTF[1] * 1.5, (int)symInfo.Digits());
         
         double risk = sig.entryPrice - sig.sl;
         sig.tp = NormalizeDouble(sig.entryPrice + risk * InpMinRR, (int)symInfo.Digits());
      }
   }
   //=== SELL TRIGGER ===
   else if(h1Trend == -1)
   {
      bool inZone = (close1 >= h1ZoneHigh - atrLTF[1] * 1.0);
      bool rsiReset = (rsiLTF[1] > 45 && rsiLTF[1] < 65);
      
      if(inZone && rsiReset && strongBearish && microDown)
      {
         sig.sellSignal = true;
         sig.entryPrice = close1;
         sig.sl         = NormalizeDouble(high1 + atrLTF[1] * 1.5, (int)symInfo.Digits());
         
         double risk = sig.sl - sig.entryPrice;
         sig.tp = NormalizeDouble(sig.entryPrice - risk * InpMinRR, (int)symInfo.Digits());
      }
   }
   
   return sig;
}

//+------------------------------------------------------------------+
//| EXECUTE BUY                                                       |
//+------------------------------------------------------------------+
bool ExecuteBuy(double price, double sl, double tp)
{
   double lots = CalcLotSize(price, sl);
   if(lots <= 0) return false;
   
   // RR validation
   double risk = price - sl;
   double reward = tp - price;
   if(reward / risk < InpMinRR)
   {
      Print("⚠️ RR too low: ", DoubleToString(reward/risk, 2));
      return false;
   }
   
   trade.SetExpertMagicNumber(InpMagicTrend);
   
   if(trade.Buy(lots, _Symbol, price, sl, tp, "XAU Trend Long"))
   {
      Print("✅ BUY | Lots: ", DoubleToString(lots, 2), 
            " | Entry: ", DoubleToString(price, (int)symInfo.Digits()),
            " | SL: ", DoubleToString(sl, (int)symInfo.Digits()),
            " | TP: ", DoubleToString(tp, (int)symInfo.Digits()));
      
      g_lastTradeTime = TimeCurrent();
      if(InpEnableAlerts) Alert("XAU EA: BUY @ ", DoubleToString(price, 2));
      return true;
   }
   else
   {
      Print("❌ Buy failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      return false;
   }
}

//+------------------------------------------------------------------+
//| EXECUTE SELL                                                      |
//+------------------------------------------------------------------+
bool ExecuteSell(double price, double sl, double tp)
{
   double lots = CalcLotSize(price, sl);
   if(lots <= 0) return false;
   
   double risk = sl - price;
   double reward = price - tp;
   if(reward / risk < InpMinRR)
   {
      Print("⚠️ RR too low: ", DoubleToString(reward/risk, 2));
      return false;
   }
   
   trade.SetExpertMagicNumber(InpMagicTrend);
   
   if(trade.Sell(lots, _Symbol, price, sl, tp, "XAU Trend Short"))
   {
      Print("✅ SELL | Lots: ", DoubleToString(lots, 2),
            " | Entry: ", DoubleToString(price, (int)symInfo.Digits()),
            " | SL: ", DoubleToString(sl, (int)symInfo.Digits()),
            " | TP: ", DoubleToString(tp, (int)symInfo.Digits()));
      
      g_lastTradeTime = TimeCurrent();
      if(InpEnableAlerts) Alert("XAU EA: SELL @ ", DoubleToString(price, 2));
      return true;
   }
   else
   {
      Print("❌ Sell failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      return false;
   }
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                                |
//+------------------------------------------------------------------+
double CalcLotSize(double entryPrice, double slPrice)
{
   double riskMoney = accInfo.Equity() * InpRiskPercent / 100.0;
   double tickValue = symInfo.TickValue();
   double tickSize  = symInfo.TickSize();
   
   if(tickValue <= 0 || tickSize <= 0) return 0;
   
   double slPoints = MathAbs(entryPrice - slPrice) / tickSize;
   double lots = riskMoney / (slPoints * tickValue);
   
   // Normalize to lot step
   double lotStep = symInfo.LotsStep();
   double minLot  = symInfo.LotsMin();
   double maxLot  = symInfo.LotsMax();
   
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   
   // Margin check
   double margin;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, entryPrice, margin))
      return 0;
   
   double freeMargin = accInfo.FreeMargin();
   if(margin > freeMargin * 0.8) // Don't use >80% margin
   {
      Print("⚠️ Insufficient margin for lots: ", lots);
      return 0;
   }
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| MANAGE OPEN POSITIONS                                             |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(!IsMyMagic(posInfo.Magic())) continue;
      
      double openPrice = posInfo.PriceOpen();
      double sl        = posInfo.StopLoss();
      double tp        = posInfo.TakeProfit();
      double current   = posInfo.PriceCurrent();
      double lots      = posInfo.Volume();
      
      //=== BREAKEVEN ===
      if(InpUseBreakeven)
      {
         double risk = MathAbs(openPrice - sl);
         double profitDist = MathAbs(current - openPrice);
         double beDist = risk * InpBreakevenRR;
         
         bool needBE = false;
         double newSl = 0;
         
         if(posInfo.PositionType() == POSITION_TYPE_BUY && profitDist >= beDist)
         {
            newSl = NormalizeDouble(openPrice + symInfo.Point() * InpBreakevenPlusPts, (int)symInfo.Digits());
            if(newSl > sl) needBE = true;
         }
         else if(posInfo.PositionType() == POSITION_TYPE_SELL && profitDist >= beDist)
         {
            newSl = NormalizeDouble(openPrice - symInfo.Point() * InpBreakevenPlusPts, (int)symInfo.Digits());
            if(newSl < sl || sl == 0) needBE = true;
         }
         
         if(needBE)
         {
            trade.PositionModify(posInfo.Ticket(), newSl, tp);
         }
      }
      
      //=== TRAILING STOP ===
      if(InpUseTrailing)
      {
         double atr[];
         ArraySetAsSeries(atr, true);
         if(CopyBuffer(g_handleAtrLTF, 0, 1, 1, atr) < 1) continue;
         
         double trailDist = atr[0] * InpTrailAtrMult;
         
         if(posInfo.PositionType() == POSITION_TYPE_BUY)
         {
            double newSl = NormalizeDouble(current - trailDist, (int)symInfo.Digits());
            if(newSl > sl && newSl > openPrice)
               trade.PositionModify(posInfo.Ticket(), newSl, tp);
         }
         else
         {
            double newSl = NormalizeDouble(current + trailDist, (int)symInfo.Digits());
            if((newSl < sl || sl == 0) && newSl < openPrice)
               trade.PositionModify(posInfo.Ticket(), newSl, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CLOSE ALL MY POSITIONS                                            |
//+------------------------------------------------------------------+
void CloseAllMyPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == _Symbol && IsMyMagic(posInfo.Magic()))
         trade.PositionClose(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| COUNT MY POSITIONS                                                |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() == _Symbol && IsMyMagic(posInfo.Magic())) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| IS MY MAGIC                                                       |
//+------------------------------------------------------------------+
bool IsMyMagic(int magic)
{
   return (magic == InpMagicTrend || magic == InpMagicRev);
}

//+------------------------------------------------------------------+
//| IS ACTIVE SESSION                                                 |
//+------------------------------------------------------------------+
bool IsActiveSession()
{
   MqlDateTime tm;
   TimeCurrent(tm);
   int h = tm.hour;
   
   if(InpTradeAsia && h >= 0 && h < 8) return true;
   if(h >= InpLondonStart && h < InpLondonEnd) return true;
   if(h >= InpNYStart && h < InpNYEnd) return true;
   return false;
}

//+------------------------------------------------------------------+
//| GET FILLING TYPE (auto-detect)                                    |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingType()
{
   long filling = 0;
   SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE, filling);
   
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| DASHBOARD CREATION                                                |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   int x = 10, y = 30;
   int lineHeight = 20;
   
   CreateLabel(g_dashPrefix + "title", x, y, "═══ XAUUSD EA MVP ═══", clrGold, 10);
   y += lineHeight + 5;
   
   CreateLabel(g_dashPrefix + "state", x, y, "State: IDLE", clrWhite, 9);
   y += lineHeight;
   
   CreateLabel(g_dashPrefix + "balance", x, y, "Balance: $0.00", clrWhite, 9);
   y += lineHeight;
   
   CreateLabel(g_dashPrefix + "equity", x, y, "Equity: $0.00", clrWhite, 9);
   y += lineHeight;
   
   CreateLabel(g_dashPrefix + "dd", x, y, "DD: 0.00%", clrWhite, 9);
   y += lineHeight;
   
   CreateLabel(g_dashPrefix + "pos", x, y, "Positions: 0/2", clrWhite, 9);
   y += lineHeight;
   
   CreateLabel(g_dashPrefix + "spread", x, y, "Spread: 0", clrWhite, 9);
   y += lineHeight;
   
   CreateLabel(g_dashPrefix + "shock", x, y, "Shock: OFF", clrLime, 9);
   y += lineHeight;
   
   CreateLabel(g_dashPrefix + "session", x, y, "Session: -", clrWhite, 9);
}

void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void UpdateDashboard()
{
   if(!InpShowDashboard) return;
   
   double ddTotal = 0, ddDay = 0;
   if(g_peakEquity > 0)
      ddTotal = (g_peakEquity - accInfo.Equity()) / g_peakEquity * 100.0;
   if(g_dayStartEquity > 0)
      ddDay = (g_dayStartEquity - accInfo.Equity()) / g_dayStartEquity * 100.0;
   
   color ddColor = clrLime;
   if(ddTotal > 5) ddColor = clrYellow;
   if(ddTotal > 10) ddColor = clrOrangeRed;
   if(ddTotal > 13) ddColor = clrRed;
   
   color shockColor = g_isNewsCooldown ? clrOrangeRed : clrLime;
   string shockText = g_isNewsCooldown ? 
      "⚡ SHOCK COOLDOWN (" + IntegerToString(g_shockCount) + ")" : "Shock: OFF";
   
   color sessionColor = IsActiveSession() ? clrLime : clrGray;
   string sessionText = IsActiveSession() ? "Session: ACTIVE" : "Session: OFF";
   
   ObjectSetString(0, g_dashPrefix + "balance", OBJPROP_TEXT, 
      "Balance: $" + DoubleToString(accInfo.Balance(), 2));
   ObjectSetString(0, g_dashPrefix + "equity", OBJPROP_TEXT, 
      "Equity: $" + DoubleToString(accInfo.Equity(), 2));
   ObjectSetString(0, g_dashPrefix + "dd", OBJPROP_TEXT, 
      "DD: " + DoubleToString(ddTotal, 2) + "% / Day: " + DoubleToString(ddDay, 2) + "%");
   ObjectSetInteger(0, g_dashPrefix + "dd", OBJPROP_COLOR, ddColor);
   ObjectSetString(0, g_dashPrefix + "pos", OBJPROP_TEXT, 
      "Positions: " + IntegerToString(CountMyPositions()) + "/" + IntegerToString(InpMaxPositions));
   ObjectSetString(0, g_dashPrefix + "spread", OBJPROP_TEXT, 
      "Spread: " + IntegerToString(symInfo.Spread()) + " pts");
   ObjectSetString(0, g_dashPrefix + "shock", OBJPROP_TEXT, shockText);
   ObjectSetInteger(0, g_dashPrefix + "shock", OBJPROP_COLOR, shockColor);
   ObjectSetString(0, g_dashPrefix + "session", OBJPROP_TEXT, sessionText);
   ObjectSetInteger(0, g_dashPrefix + "session", OBJPROP_COLOR, sessionColor);
}
//+------------------------------------------------------------------+
