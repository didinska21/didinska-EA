//+------------------------------------------------------------------+
//|                                     HTF_Trend_Pullback_Main.mq5  |
//|                                  Copyright 2026, AI Collaborator |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

input group "=== GENERAL SETTINGS ==="
input int      InpMagicNumber   = 889900;       
input string   InpTradeComment  = "XAU_Pullback"; 

input group "=== RISK MANAGEMENT (THE GUARDIAN) ==="
input double   InpRiskPercent   = 1.0;          
input double   InpTargetPercent = 2.0;          
input double   InpMaxLotSize    = 0.05;         
input int      InpMinStopLoss   = 300;          

input group "=== EXECUTION & SAFETY ==="
input int      InpMaxSpread     = 50;           
input int      InpMaxRetries    = 3;            
input int      InpSlippage      = 30;           

input group "=== INDICATOR PARAMETERS ==="
input int      InpEmaFast       = 50;           
input int      InpEmaSlow       = 200;          
input int      InpRsiPeriod     = 14;           
input int      InpEmaPullback   = 21;           

datetime       lastBarTime;     
int            handleEmaH4Fast;
int            handleEmaH4Slow;
int            handleRsiH1;
int            handleEmaM15;
int            handleStochM15;
int            handleAtrM15;

// --- MENGGABUNGKAN FILE PHASE 5 & 6 ---
#include "RiskManagement.mqh"
#include "ExecutionEngine.mqh"

int OnInit()
{
   if(StringFind(_Symbol, "XAUUSD") < 0 && StringFind(_Symbol, "GOLD") < 0) return(INIT_FAILED);
   if(_Period != PERIOD_M15) return(INIT_FAILED);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);

   handleEmaH4Fast  = iMA(_Symbol, PERIOD_H4, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   handleEmaH4Slow  = iMA(_Symbol, PERIOD_H4, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   handleRsiH1      = iRSI(_Symbol, PERIOD_H1, InpRsiPeriod, PRICE_CLOSE);
   handleEmaM15     = iMA(_Symbol, PERIOD_M15, InpEmaPullback, 0, MODE_EMA, PRICE_CLOSE);
   handleStochM15   = iStochastic(_Symbol, PERIOD_M15, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   handleAtrM15     = iATR(_Symbol, PERIOD_M15, 14);

   lastBarTime = 0;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(handleEmaH4Fast); IndicatorRelease(handleEmaH4Slow);
   IndicatorRelease(handleRsiH1); IndicatorRelease(handleEmaM15);
   IndicatorRelease(handleStochM15); IndicatorRelease(handleAtrM15);
}

void OnTick()
{
   CheckRiskManagement();
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime == lastBarTime) return; 
   
   lastBarTime = currentBarTime;
   ProcessTradingLogic();
}

void CheckRiskManagement()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double profit = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
      }
   }

   double lossPercent = (profit < 0) ? (MathAbs(profit) / balance) * 100.0 : 0.0;
   double profitPercent = (profit > 0) ? (profit / balance) * 100.0 : 0.0;

   if(lossPercent >= InpRiskPercent || profitPercent >= InpTargetPercent) CloseAllPositionsWithRetry();
}

void CloseAllPositionsWithRetry()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         bool closed = false; int attempts = 0;
         while(!closed && attempts < InpMaxRetries)
         {
            attempts++;
            if(trade.PositionClose(ticket)) closed = true;
            else Sleep(150); 
         }
      }
   }
}
