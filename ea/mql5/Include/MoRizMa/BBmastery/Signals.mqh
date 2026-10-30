//+------------------------------------------------------------------+
//| Signals.mqh                                                      |
//| CT / CC candidates, TRZ warnings, band regime (spec 6, 15, 16)   |
//+------------------------------------------------------------------+
#ifndef MORIZMA_BBM_SIGNALS_MQH
#define MORIZMA_BBM_SIGNALS_MQH

#include "Defines.mqh"

//--- Spec 6.1: BullCandidate = C > max(H5, H10, M) — strict inequality (U03)
bool BBM_BullCandidate(const BBMBar &b, const bool colourFilter)
  {
   double ref = MathMax(MathMax(b.h5, b.h10), b.middle);
   if(!(b.close > ref))
      return false;
   if(colourFilter && !(b.close > b.open))
      return false;
   return true;
  }

//--- Spec 6.1: BearCandidate = C < min(L5, L10, M)
bool BBM_BearCandidate(const BBMBar &b, const bool colourFilter)
  {
   double ref = MathMin(MathMin(b.l5, b.l10), b.middle);
   if(!(b.close < ref))
      return false;
   if(colourFilter && !(b.close < b.open))
      return false;
   return true;
  }

//--- Spec 6.3: CC — close outside an outer band (diagnostic only in v1)
bool BBM_BullCC(const BBMBar &b) { return (b.close > b.upper); }
bool BBM_BearCC(const BBMBar &b) { return (b.close < b.lower); }

//--- Spec 15: proposed TRZ warning predicates — diagnostic only, never trade
bool BBM_SellWarning(const BBMBar &b) { return (MathMax(b.h5, b.h10) >= b.upper); }
bool BBM_BuyWarning(const BBMBar &b)  { return (MathMin(b.l5, b.l10) <= b.lower); }

//--- Spec 6.2: event detection on completed bars [1] and [2]
bool BBM_IsEvent(const bool now, const bool prev, const ENUM_BBM_EVENT_MODE mode)
  {
   if(!now)
      return false;
   if(mode == BBM_EVENT_EVERY_QUALIFYING_BAR)
      return true;
   return !prev;
  }

//--- Spec 16: regime diagnostics from bar [1] and bar [1+k]
void BBM_ComputeRegime(const BBMBar &b1, const BBMBar &b1k, const int k, BBMRegime &r)
  {
   r.valid        = false;
   r.width        = b1.upper - b1.lower;
   r.norm_width   = 0.0;
   r.middle_slope = 0.0;
   r.width_change = 0.0;

   double widthK = b1k.upper - b1k.lower;
   if(k <= 0 || b1.atr <= 0.0 || r.width <= 0.0 || widthK <= 0.0)
      return;

   r.norm_width   = r.width / b1.atr;
   r.middle_slope = (b1.middle - b1k.middle) / (k * b1.atr);
   r.width_change = r.width / widthK - 1.0;
   r.valid        = true;
  }

#endif
