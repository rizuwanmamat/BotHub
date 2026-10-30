//+------------------------------------------------------------------+
//| Risk.mqh                                                         |
//| Volume sizing and daily equity protection (spec section 11)      |
//+------------------------------------------------------------------+
#ifndef MORIZMA_BBM_RISK_MQH
#define MORIZMA_BBM_RISK_MQH

#include "Defines.mqh"

//--- Number of decimals implied by the broker volume step
int BBM_VolumeDigits(const double step)
  {
   if(step <= 0.0 || step >= 1.0)
      return 0;
   return (int)MathCeil(-MathLog10(step) - 1e-9);
  }

//--- Round DOWN to the volume step, cap at max. Never round up (spec 11).
bool BBM_NormaliseVolume(const string symbol, const double raw, double &vol, string &reason)
  {
   double vmin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0 || vmin <= 0.0)
     {
      reason = BBM_R_VOLUME_BELOW_MIN;
      return false;
     }

   double v = MathFloor(raw / vstep + 1e-9) * vstep;
   if(vmax > 0.0 && v > vmax)
      v = MathFloor(vmax / vstep + 1e-9) * vstep;
   v = NormalizeDouble(v, BBM_VolumeDigits(vstep));

   if(v < vmin - 1e-12)
     {
      reason = BBM_R_VOLUME_BELOW_MIN;
      return false;
     }
   vol = v;
   return true;
  }

//--- Account-currency loss from entry to stop for 1.0 lot, plus commission allowance
bool BBM_LossPerLot(const string symbol, const int dir, const double entry, const double sl,
                    const double commissionPerLot, double &lossPerLot)
  {
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double pl = 0.0;
   if(!OrderCalcProfit(type, symbol, 1.0, entry, sl, pl))
      return false;
   lossPerLot = MathAbs(pl) + MathMax(0.0, commissionPerLot);
   return (lossPerLot > 0.0);
  }

//--- EQUITY_RISK or FIXED_LOT sizing; outputs normalised volume and planned risk
bool BBM_ComputeVolume(const string symbol, const int dir, const double entry, const double sl,
                       const ENUM_BBM_VOLUME_MODE mode, const double fixedLot,
                       const double riskPct, const double commissionPerLot,
                       double &vol, double &plannedRisk, string &reason)
  {
   double lossPerLot = 0.0;
   if(!BBM_LossPerLot(symbol, dir, entry, sl, commissionPerLot, lossPerLot))
     {
      reason = BBM_R_STOP_INVALID;
      return false;
     }

   double raw = fixedLot;
   if(mode == BBM_VOLUME_EQUITY_RISK)
     {
      double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * riskPct / 100.0;
      raw = riskMoney / lossPerLot;
     }

   if(!BBM_NormaliseVolume(symbol, raw, vol, reason))
      return false;

   plannedRisk = vol * lossPerLot;
   return true;
  }

//--- Free-margin check using the broker's own margin calculation
bool BBM_MarginOk(const string symbol, const int dir, const double vol, const double price)
  {
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double margin = 0.0;
   if(!OrderCalcMargin(type, symbol, vol, price, margin))
      return false;
   return (margin < AccountInfoDouble(ACCOUNT_MARGIN_FREE));
  }

//+------------------------------------------------------------------+
//| Daily equity protection on broker-server day boundaries          |
//+------------------------------------------------------------------+
class CBBMDailyGuard
  {
public:
   datetime          day;
   double            start_equity;
   bool              locked;
   bool              partial;      // anchor taken mid-day without history

                     CBBMDailyGuard(void) : day(0), start_equity(0.0), locked(false), partial(true) {}

   static datetime   ServerDay(void)
     {
      datetime now = TimeTradeServer();
      return now - (now % 86400);
     }

   //--- Returns true when the day rolled over (lock released)
   bool              Roll(void)
     {
      datetime d = ServerDay();
      if(d == day)
         return false;
      bool firstEver = (day == 0);
      day          = d;
      start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      locked       = false;
      partial      = firstEver;
      return !firstEver;
     }

   //--- Returns true at the moment the limit is breached
   bool              CheckBreach(const double limitPct)
     {
      if(locked || start_equity <= 0.0 || limitPct <= 0.0)
         return false;
      double loss = MathMax(0.0, start_equity - AccountInfoDouble(ACCOUNT_EQUITY));
      if(loss >= start_equity * limitPct / 100.0)
        {
         locked = true;
         return true;
        }
      return false;
     }
  };

#endif
