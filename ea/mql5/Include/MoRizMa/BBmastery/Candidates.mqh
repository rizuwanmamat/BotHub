//+------------------------------------------------------------------+
//| Candidates.mqh                                                   |
//| Entry-zone geometry and tick retest detection (spec 7)           |
//+------------------------------------------------------------------+
#ifndef MORIZMA_BBM_CANDIDATES_MQH
#define MORIZMA_BBM_CANDIDATES_MQH

#include "Defines.mqh"

enum ENUM_BBM_RETEST
  {
   BBM_RETEST_NONE  = 0,
   BBM_RETEST_TOUCH = 1,
   BBM_RETEST_GAP   = 2
  };

//--- Buy zone [min(L5,L10), max(L5,L10)]; sell zone [min(H5,H10), max(H5,H10)]
void BBM_ZoneFromBar(const int dir, const BBMBar &b, double &lo, double &hi)
  {
   if(dir > 0)
     {
      lo = MathMin(b.l5, b.l10);
      hi = MathMax(b.l5, b.l10);
     }
   else
     {
      lo = MathMin(b.h5, b.h10);
      hi = MathMax(b.h5, b.h10);
     }
  }

//--- +1 above zone, 0 inside (tolerance inclusive), -1 below
int BBM_RelPos(const double ref, const double lo, const double hi, const double tol)
  {
   if(ref > hi + tol) return 1;
   if(ref < lo - tol) return -1;
   return 0;
  }

void BBM_ResetCandidate(BBMCandidate &c)
  {
   //--- Field-by-field: the struct holds strings, so ZeroMemory is avoided
   c.id              = 0;
   c.dir             = 0;
   c.origin          = "CT";
   c.signal_time     = 0;
   c.bars_since      = 0;
   c.ctx_dir         = 0;
   c.cc_coexist      = false;
   ZeroMemory(c.sig);
   ZeroMemory(c.regime);
   c.seen_trend_side = false;
   c.last_pos        = 99;
   c.extreme         = 0.0;
   c.touch_time      = 0;
   c.touch_price     = 0.0;
   c.touch_lo        = 0.0;
   c.touch_hi        = 0.0;
   c.touch_boundary  = 0.0;
   c.touch_kind      = "";
   c.confirm_bars    = 0;
  }

//+------------------------------------------------------------------+
//| Update retest state with one Bid tick against the current zone.  |
//| A touch requires price first observed on the trend side (buy:    |
//| above zone; sell: below), then a return into the zone. A jump    |
//| from the trend side straight through to the far side is a gap:   |
//| no fill is invented and a fresh trend-side observation is needed.|
//+------------------------------------------------------------------+
ENUM_BBM_RETEST BBM_UpdateRetest(BBMCandidate &c, const double ref, const double prevRef,
                                 const double lo, const double hi, const double tol)
  {
   int pos   = BBM_RelPos(ref, lo, hi, tol);
   int trend = (c.dir > 0) ? 1 : -1;
   ENUM_BBM_RETEST result = BBM_RETEST_NONE;

   if(pos == trend)
      c.seen_trend_side = true;
   else if(c.seen_trend_side)
     {
      if(pos == 0)
        {
         result = BBM_RETEST_TOUCH;
         //--- LIVE zones can move onto a stationary price; log which happened
         bool prevInsideNow = (prevRef > 0.0 && BBM_RelPos(prevRef, lo, hi, tol) == 0);
         c.touch_kind = prevInsideNow ? "ZONE_TO_PRICE" : "PRICE_INTO_ZONE";
        }
      else if(pos == -trend)
        {
         if(c.last_pos == trend)
            result = BBM_RETEST_GAP;
         c.seen_trend_side = false;
        }
     }
   c.last_pos = pos;
   return result;
  }

#endif
