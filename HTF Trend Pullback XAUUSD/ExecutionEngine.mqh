//+------------------------------------------------------------------+
//|                                              ExecutionEngine.mqh |
//+------------------------------------------------------------------+

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         count++;
      }
   }
   return count;
}

void ExecuteTrade(int orderType, double atrValue)
{
   double slDistancePoints = (atrValue * 1.5) / _Point; 
   if(slDistancePoints < InpMinStopLoss) slDistancePoints = InpMinStopLoss;
   
   double tpDistancePoints = slDistancePoints * 2.0;
   double lotSize = CalculateDynamicLotSize(slDistancePoints);

   double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice = 0.0; double tpPrice = 0.0;

   if(orderType == ORDER_TYPE_BUY)
   {
      slPrice = currentPrice - (slDistancePoints * _Point);
      tpPrice = currentPrice + (tpDistancePoints * _Point);
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      slPrice = currentPrice + (slDistancePoints * _Point);
      tpPrice = currentPrice - (tpDistancePoints * _Point);
   }

   slPrice = NormalizeDouble(slPrice, _Digits);
   tpPrice = NormalizeDouble(tpPrice, _Digits);

   if(orderType == ORDER_TYPE_BUY) trade.Buy(lotSize, _Symbol, currentPrice, slPrice, tpPrice, InpTradeComment);
   else if(orderType == ORDER_TYPE_SELL) trade.Sell(lotSize, _Symbol, currentPrice, slPrice, tpPrice, InpTradeComment);
}

void ProcessTradingLogic()
{
   if(CountOpenPositions() > 0) return;

   double emaH4Fast[], emaH4Slow[], rsiH1[], emaM15[], atrM15[], stochMain[], stochSignal[];
   ArraySetAsSeries(emaH4Fast, true); ArraySetAsSeries(emaH4Slow, true);
   ArraySetAsSeries(rsiH1, true); ArraySetAsSeries(emaM15, true);
   ArraySetAsSeries(atrM15, true); ArraySetAsSeries(stochMain, true); ArraySetAsSeries(stochSignal, true);

   if(CopyBuffer(handleEmaH4Fast, 0, 1, 2, emaH4Fast) <= 0 || CopyBuffer(handleEmaH4Slow, 0, 1, 2, emaH4Slow) <= 0 ||
      CopyBuffer(handleRsiH1, 0, 1, 2, rsiH1) <= 0 || CopyBuffer(handleEmaM15, 0, 1, 2, emaM15) <= 0 ||
      CopyBuffer(handleAtrM15, 0, 1, 2, atrM15) <= 0 || CopyBuffer(handleStochM15, 0, 1, 2, stochMain) <= 0 ||
      CopyBuffer(handleStochM15, 1, 1, 2, stochSignal) <= 0) return; 

   bool isUptrendH4 = (emaH4Fast[0] > emaH4Slow[0]);
   bool isDowntrendH4 = (emaH4Fast[0] < emaH4Slow[0]);
   bool isBullishRsi = (rsiH1[0] > 50);
   bool isBearishRsi = (rsiH1[0] < 50);

   double lowM15 = iLow(_Symbol, PERIOD_M15, 1); double highM15 = iHigh(_Symbol, PERIOD_M15, 1);
   bool stochCrossUp = (stochMain[1] < 20 && stochMain[0] > stochSignal[0] && stochMain[1] <= stochSignal[1]);
   bool stochCrossDown = (stochMain[1] > 80 && stochMain[0] < stochSignal[0] && stochMain[1] >= stochSignal[1]);

   if(isUptrendH4 && isBullishRsi && lowM15 <= emaM15[0] && stochCrossUp) ExecuteTrade(ORDER_TYPE_BUY, atrM15[0]);
   else if(isDowntrendH4 && isBearishRsi && highM15 >= emaM15[0] && stochCrossDown) ExecuteTrade(ORDER_TYPE_SELL, atrM15[0]);
}
