//+------------------------------------------------------------------+
//| Exits.mqh                                                        |
//| SL/TP construction for the three exit policies (spec 10)         |
//+------------------------------------------------------------------+
#ifndef MORIZMA_BBM_EXITS_MQH
#define MORIZMA_BBM_EXITS_MQH

#include "Defines.mqh"
#include "Execution.mqh"

struct BBMExitParams
  {
   ENUM_BBM_EXIT_POLICY policy;
   int               fixed_sl_points;
   int               fixed_tp_points;
   int               structure_buffer_points;
   double            rr_multiple;
   int               min_stop_points;
   int               max_stop_points;
   int               min_target_points;
  };

//+------------------------------------------------------------------+
//| entry      : requested price before the fill, actual fill after  |
//| extreme    : causal lowest low (buy) / highest high (sell)       |
//| frozenBand : last completed Setup upper (buy) / lower (sell) BB  |
//| keepSL     : when > 0 the stop is kept (post-fill reconcile of   |
//|              structural stops — the structure level is fixed)    |
//+------------------------------------------------------------------+
bool BBM_ComputeExit(const string symbol, const BBMExitParams &p, const int dir,
                     const double entry, const double extreme, const double frozenBand,
                     const double keepSL, double &sl, double &tp, string &reason)
  {
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   sl = 0.0;
   tp = 0.0;

   //--- 10.1 FIXED
   if(p.policy == BBM_EXIT_FIXED)
     {
      if(p.fixed_sl_points <= 0) { reason = BBM_R_STOP_INVALID;   return false; }
      if(p.fixed_tp_points <= 0) { reason = BBM_R_TARGET_INVALID; return false; }
      sl = entry - dir * p.fixed_sl_points * point;
      tp = entry + dir * p.fixed_tp_points * point;
      sl = BBM_NormalisePrice(symbol, sl);
      tp = BBM_NormalisePrice(symbol, tp);
      return true;
     }

   //--- 10.2 / 10.3 structural stop
   if(keepSL > 0.0)
      sl = keepSL;
   else
     {
      if(extreme <= 0.0) { reason = BBM_R_STOP_INVALID; return false; }
      sl = extreme - dir * p.structure_buffer_points * point;
     }
   sl = BBM_NormalisePrice(symbol, sl);

   double dist = (entry - sl) * dir;
   if(dist <= 0.0)
     { reason = BBM_R_STOP_INVALID; return false; }
   if(p.min_stop_points > 0 && dist < p.min_stop_points * point)
     { reason = BBM_R_STOP_INVALID; return false; }
   if(p.max_stop_points > 0 && dist > p.max_stop_points * point)
     { reason = BBM_R_STOP_INVALID; return false; }

   if(p.policy == BBM_EXIT_STRUCTURE_RR)
     {
      if(p.rr_multiple <= 0.0) { reason = BBM_R_TARGET_INVALID; return false; }
      tp = BBM_NormalisePrice(symbol, entry + dir * dist * p.rr_multiple);
      return true;
     }

   //--- 10.3 FROZEN_OUTER_BAND target
   if(frozenBand <= 0.0) { reason = BBM_R_TARGET_INVALID; return false; }
   tp = BBM_NormalisePrice(symbol, frozenBand);
   double room = (tp - entry) * dir;
   if(room <= MathMax(0, p.min_target_points) * point)
     { reason = BBM_R_TARGET_INVALID; return false; }
   return true;
  }

#endif
