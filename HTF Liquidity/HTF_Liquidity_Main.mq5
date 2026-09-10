//+------------------------------------------------------------------+
//|                                    HTF_Liquidity_Sweep_XAUUSD.mq5|
//|                                  Copyright 2026, AI Collaborator |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

input group "=== GENERAL SETTINGS ==="
input int      InpMagicNumber   = 998877;       // Magic Number Baru
input string   InpTradeComment  = "Liquidity_Sweep"; 

input group "=== RISK MANAGEMENT (THE GUARDIAN) ==="
input double   InpRiskPercent   = 1.0;          // Max Risk per Trade (%)
input double   InpTargetPercent = 2.0;          // Max Target Profit (%)
input double   InpMaxLotSize    = 0.05;         // Hard Limit Max Lot
input int      InpMinStopLoss   = 250;          // Minimum SL Points

input group "=== EXECUTION & SAFETY ==="
input int      InpMaxRetries    = 3;            
input int      InpSlippage      = 30;           

datetime       lastBarTime;     

#include "RiskManagement_V2.mqh"
#include "ExecutionEngine_V2.mqh"

int OnInit()
{
   if(StringFind(_Symbol, "XAUUSD") < 0 && StringFind(_Symbol, "GOLD") < 0) return(INIT_FAILED);
   if(_Period != PERIOD_M15) return(INIT_FAILED);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   lastBarTime = 0;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

void OnTick()
{
   CheckRiskManagement();
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime == lastBarTime) return; 
   
   lastBarTime = currentBarTime;
   ProcessPriceActionLogic();
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
