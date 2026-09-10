//+------------------------------------------------------------------+
//|                                          ExecutionEngine_V2.mqh  |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) count++;
   }
   return count;
}

void ExecuteTrade(int orderType, double slPrice, double tpPrice)
{
   double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPoints = MathAbs(currentPrice - slPrice) / _Point;
   
   if(slPoints < InpMinStopLoss) slPoints = InpMinStopLoss;
   double lotSize = CalculateDynamicLotSize(slPoints);

   slPrice = NormalizeDouble(slPrice, _Digits);
   tpPrice = NormalizeDouble(tpPrice, _Digits);

   if(orderType == ORDER_TYPE_BUY) trade.Buy(lotSize, _Symbol, currentPrice, slPrice, tpPrice, InpTradeComment);
   else if(orderType == ORDER_TYPE_SELL) trade.Sell(lotSize, _Symbol, currentPrice, slPrice, tpPrice, InpTradeComment);
}

void ProcessPriceActionLogic()
{
   if(CountOpenPositions() > 0) return;

   // Mendeteksi Swing High dan Swing Low dari 5 candle sebelumnya (Index 2 s.d 6)
   double highestHigh = 0;
   double lowestLow = 999999;
   
   for(int i = 2; i <= 6; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M15, i);
      double l = iLow(_Symbol, PERIOD_M15, i);
      if(h > highestHigh) highestHigh = h;
      if(l < lowestLow) lowestLow = l;
   }

   // Candle referensi saat ini (Index 1 = candle yang baru ditutup)
   double open1  = iOpen(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1  = iHigh(_Symbol, PERIOD_M15, 1);
   double low1   = iLow(_Symbol, PERIOD_M15, 1);

   // Logika Liquidity Sweep & Rejection (Buy Setup)
   // Harga sempat menembus bawah Swing Low (Low < lowestLow), namun close kembali di atasnya (Bullish Rejection)
   bool sweepLow = (low1 < lowestLow && close1 > lowestLow && close1 > open1);
   if(sweepLow)
   {
      double slPrice = low1 - (100 * _Point); // SL di bawah sumbu ekor terbawah
      double tpPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID) + (MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_BID) - slPrice) * 2.0);
      ExecuteTrade(ORDER_TYPE_BUY, slPrice, tpPrice);
      return;
   }

   // Logika Liquidity Sweep & Rejection (Sell Setup)
   // Harga sempat menembus atas Swing High (High > highestHigh), namun close kembali di bawahnya (Bearish Rejection)
   bool sweepHigh = (high1 > highestHigh && close1 < highestHigh && close1 < open1);
   if(sweepHigh)
   {
      double slPrice = high1 + (100 * _Point); // SL di atas sumbu ekor teratas
      double tpPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - (MathAbs(slPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) * 2.0);
      ExecuteTrade(ORDER_TYPE_SELL, slPrice, tpPrice);
      return;
   }
}
