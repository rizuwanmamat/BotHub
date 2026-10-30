//+------------------------------------------------------------------+
//| Context.mqh                                                      |
//| Higher-timeframe context direction (spec 6.4)                    |
//+------------------------------------------------------------------+
#ifndef MORIZMA_BBM_CONTEXT_MQH
#define MORIZMA_BBM_CONTEXT_MQH

#include "Defines.mqh"

//--- Returns +1 bull, -1 bear, 0 neutral. With mode OFF the
//--- MIDDLE_AND_EMA50 definition is still computed for logging.
int BBM_ContextDirection(const BBMBar &c, const ENUM_BBM_CONTEXT_MODE mode)
  {
   if(mode == BBM_CONTEXT_MIDDLE_BAND_ONLY)
     {
      if(c.close > c.middle) return 1;
      if(c.close < c.middle) return -1;
      return 0;
     }
   if(c.close > c.middle && c.close > c.e50) return 1;
   if(c.close < c.middle && c.close < c.e50) return -1;
   return 0;
  }

//--- Neutral blocks new entries; it is never a reversal signal.
bool BBM_ContextPermits(const int dir, const int ctxDir, const ENUM_BBM_CONTEXT_MODE mode)
  {
   if(mode == BBM_CONTEXT_OFF)
      return true;
   return (ctxDir == dir);
  }

#endif
