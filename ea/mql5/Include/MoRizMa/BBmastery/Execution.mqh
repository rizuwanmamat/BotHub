//+------------------------------------------------------------------+
//| Execution.mqh                                                    |
//| Ownership checks, stop validation, order submission (spec 12)    |
//+------------------------------------------------------------------+
#ifndef MORIZMA_BBM_EXECUTION_MQH
#define MORIZMA_BBM_EXECUTION_MQH

#include <Trade/Trade.mqh>
#include "Defines.mqh"

//--- Round to the symbol tick size, then to digits
double BBM_NormalisePrice(const string symbol, const double price)
  {
   double tick   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double p      = price;
   if(tick > 0.0)
      p = MathRound(p / tick) * tick;
   return NormalizeDouble(p, digits);
  }

class CBBMExecution
  {
private:
   CTrade            m_trade;
   string            m_symbol;
   ulong             m_magic;

public:
   uint              last_retcode;
   string            last_comment;
   ulong             last_order;
   ulong             last_deal;
   double            last_price;
   double            last_volume;

   bool              Init(const string symbol, const ulong magic, const ulong deviationPoints)
     {
      m_symbol = symbol;
      m_magic  = magic;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(deviationPoints);
      m_trade.SetMarginMode();
      m_trade.SetAsyncMode(false);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      return m_trade.SetTypeFillingBySymbol(symbol);
     }

   bool              IsNetting(void) const
     {
      return ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) ==
              ACCOUNT_MARGIN_MODE_RETAIL_NETTING);
     }

   //--- Number of positions on this symbol owned by this EA; returns the first ticket
   int               OwnedPositions(ulong &ticket) const
     {
      int n = 0;
      ticket = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         if(n == 0)
            ticket = t;
         n++;
        }
      return n;
     }

   //--- Any position on this symbol NOT owned by this EA
   bool              ForeignExposure(void) const
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            return true;
        }
      return false;
     }

   //--- In-flight orders owned by this EA on this symbol
   int               OwnedOrders(void) const
     {
      int n = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong t = OrderGetTicket(i);
         if(t == 0)
            continue;
         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic)
            n++;
        }
      return n;
     }

   //--- Netting: ownership cannot be separated by magic, so refuse (spec 12)
   bool              OwnershipConflict(void) const
     {
      return (IsNetting() && ForeignExposure());
     }

   bool              MarketOpenFor(const int dir) const
     {
      ENUM_SYMBOL_TRADE_MODE mode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_MODE);
      if(mode == SYMBOL_TRADE_MODE_FULL)
         return true;
      if(mode == SYMBOL_TRADE_MODE_LONGONLY)
         return (dir > 0);
      if(mode == SYMBOL_TRADE_MODE_SHORTONLY)
         return (dir < 0);
      return false;
     }

   //--- SL/TP vs broker stops level, measured from the price that triggers them
   bool              StopsValid(const int dir, const double sl, const double tp, string &reason) const
     {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double level = (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
      double bid   = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      if(dir > 0)
        {
         if(sl <= 0.0 || bid - sl <= level) { reason = BBM_R_STOP_INVALID;   return false; }
         if(tp <= 0.0 || tp - bid <= level) { reason = BBM_R_TARGET_INVALID; return false; }
        }
      else
        {
         if(sl <= 0.0 || sl - ask <= level) { reason = BBM_R_STOP_INVALID;   return false; }
         if(tp <= 0.0 || ask - tp <= level) { reason = BBM_R_TARGET_INVALID; return false; }
        }
      return true;
     }

   //--- Modification is blocked while price is inside the freeze level
   bool              OutsideFreeze(const int dir, const double sl, const double tp) const
     {
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double freeze = (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
      if(freeze <= 0.0)
         return true;
      double ref = (dir > 0) ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                             : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      return (MathAbs(ref - sl) > freeze && MathAbs(tp - ref) > freeze);
     }

   //--- One synchronous market request with provisional protection attached
   bool              Open(const int dir, const double vol, const double price,
                          const double sl, const double tp, const string comment)
     {
      ResetLastError();
      bool sent = (dir > 0) ? m_trade.Buy(vol, m_symbol, price, sl, tp, comment)
                            : m_trade.Sell(vol, m_symbol, price, sl, tp, comment);
      last_retcode = m_trade.ResultRetcode();
      last_comment = m_trade.ResultComment();
      last_order   = m_trade.ResultOrder();
      last_deal    = m_trade.ResultDeal();
      last_price   = m_trade.ResultPrice();
      last_volume  = m_trade.ResultVolume();
      return (sent && (last_retcode == TRADE_RETCODE_DONE ||
                       last_retcode == TRADE_RETCODE_DONE_PARTIAL ||
                       last_retcode == TRADE_RETCODE_PLACED));
     }

   bool              Modify(const ulong ticket, const double sl, const double tp)
     {
      bool ok = m_trade.PositionModify(ticket, sl, tp);
      last_retcode = m_trade.ResultRetcode();
      last_comment = m_trade.ResultComment();
      return (ok && last_retcode == TRADE_RETCODE_DONE);
     }

   bool              Close(const ulong ticket)
     {
      bool ok = m_trade.PositionClose(ticket);
      last_retcode = m_trade.ResultRetcode();
      last_comment = m_trade.ResultComment();
      return (ok && (last_retcode == TRADE_RETCODE_DONE || last_retcode == TRADE_RETCODE_PLACED));
     }

   //--- Close only this EA's positions on this symbol (never unrelated ones)
   bool              CloseAllOwned(void)
     {
      bool allOk = true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
            (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         if(!Close(t))
            allOk = false;
        }
      return allOk;
     }

   //--- Retcodes that mean the outcome is unknown: reconcile, never resend blindly
   static bool       IsUncertain(const uint retcode)
     {
      return (retcode == 0 ||
              retcode == TRADE_RETCODE_TIMEOUT ||
              retcode == TRADE_RETCODE_CONNECTION ||
              retcode == TRADE_RETCODE_ERROR);
     }
  };

#endif
