//+------------------------------------------------------------------+
//|                                           RiskManagement_V2.mqh|
//+------------------------------------------------------------------+
double CalculateDynamicLotSize(double slPoints)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(slPoints <= 0 || tickValue <= 0) return 0.01; 
   
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   double moneyPerPoint = (tickValue / tickSize) * point;
   double calculatedLot = riskMoney / (slPoints * moneyPerPoint);
   
   calculatedLot = NormalizeDouble(MathRound(calculatedLot / lotStep) * lotStep, 2);
   
   if(calculatedLot < minLot) calculatedLot = minLot;
   if(calculatedLot > InpMaxLotSize) calculatedLot = InpMaxLotSize;
   if(calculatedLot > maxLot) calculatedLot = maxLot;
   
   return calculatedLot;
}
