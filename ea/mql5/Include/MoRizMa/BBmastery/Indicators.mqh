//+------------------------------------------------------------------+
//| Indicators.mqh                                                   |
//| Native MT5 indicator handles for one timeframe (spec section 4)  |
//+------------------------------------------------------------------+
#ifndef MORIZMA_BBM_INDICATORS_MQH
#define MORIZMA_BBM_INDICATORS_MQH

#include "Defines.mqh"

//--- iBands buffer mapping per MQL5 docs: 0 BASE_LINE, 1 UPPER_BAND, 2 LOWER_BAND.
//--- Verify against the plotted chart before trusting results (spec 4).
#define BBM_BB_MIDDLE 0
#define BBM_BB_UPPER  1
#define BBM_BB_LOWER  2

class CBBMIndicators
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_hBB;
   int               m_hH5;
   int               m_hH10;
   int               m_hL5;
   int               m_hL10;
   int               m_hE50;
   int               m_hATR;

   bool              CopyOne(const int handle, const int buffer, const int shift, double &value);

public:
                     CBBMIndicators(void);
                    ~CBBMIndicators(void) { Release(); }

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                          const int bbPeriod, const double bbDeviation,
                          const int fastMA, const int slowMA,
                          const int emaPeriod, const int atrPeriod);
   void              Release(void);
   bool              Ready(const int minBars);
   bool              GetBar(const int shift, BBMBar &bar);
   ENUM_TIMEFRAMES   Timeframe(void) const { return m_tf; }
  };

//+------------------------------------------------------------------+
CBBMIndicators::CBBMIndicators(void) : m_symbol(""), m_tf(PERIOD_CURRENT),
   m_hBB(INVALID_HANDLE), m_hH5(INVALID_HANDLE), m_hH10(INVALID_HANDLE),
   m_hL5(INVALID_HANDLE), m_hL10(INVALID_HANDLE), m_hE50(INVALID_HANDLE),
   m_hATR(INVALID_HANDLE)
  {
  }

//+------------------------------------------------------------------+
bool CBBMIndicators::Init(const string symbol, const ENUM_TIMEFRAMES tf,
                          const int bbPeriod, const double bbDeviation,
                          const int fastMA, const int slowMA,
                          const int emaPeriod, const int atrPeriod)
  {
   Release();
   m_symbol = symbol;
   m_tf     = tf;

   m_hBB  = iBands(symbol, tf, bbPeriod, 0, bbDeviation, PRICE_CLOSE);
   m_hH5  = iMA(symbol, tf, fastMA, 0, MODE_LWMA, PRICE_HIGH);
   m_hH10 = iMA(symbol, tf, slowMA, 0, MODE_LWMA, PRICE_HIGH);
   m_hL5  = iMA(symbol, tf, fastMA, 0, MODE_LWMA, PRICE_LOW);
   m_hL10 = iMA(symbol, tf, slowMA, 0, MODE_LWMA, PRICE_LOW);
   m_hE50 = iMA(symbol, tf, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_hATR = iATR(symbol, tf, atrPeriod);

   if(m_hBB == INVALID_HANDLE || m_hH5 == INVALID_HANDLE || m_hH10 == INVALID_HANDLE ||
      m_hL5 == INVALID_HANDLE || m_hL10 == INVALID_HANDLE || m_hE50 == INVALID_HANDLE ||
      m_hATR == INVALID_HANDLE)
     {
      PrintFormat("BBM: indicator handle creation failed on %s %s, error %d",
                  symbol, EnumToString(tf), GetLastError());
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
void CBBMIndicators::Release(void)
  {
   if(m_hBB  != INVALID_HANDLE) { IndicatorRelease(m_hBB);  m_hBB  = INVALID_HANDLE; }
   if(m_hH5  != INVALID_HANDLE) { IndicatorRelease(m_hH5);  m_hH5  = INVALID_HANDLE; }
   if(m_hH10 != INVALID_HANDLE) { IndicatorRelease(m_hH10); m_hH10 = INVALID_HANDLE; }
   if(m_hL5  != INVALID_HANDLE) { IndicatorRelease(m_hL5);  m_hL5  = INVALID_HANDLE; }
   if(m_hL10 != INVALID_HANDLE) { IndicatorRelease(m_hL10); m_hL10 = INVALID_HANDLE; }
   if(m_hE50 != INVALID_HANDLE) { IndicatorRelease(m_hE50); m_hE50 = INVALID_HANDLE; }
   if(m_hATR != INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR = INVALID_HANDLE; }
  }

//+------------------------------------------------------------------+
//| Skip evaluation when history or handles are incomplete (spec 4)  |
//+------------------------------------------------------------------+
bool CBBMIndicators::Ready(const int minBars)
  {
   if(Bars(m_symbol, m_tf) < minBars)
      return false;
   int handles[7];
   handles[0] = m_hBB;  handles[1] = m_hH5;  handles[2] = m_hH10;
   handles[3] = m_hL5;  handles[4] = m_hL10; handles[5] = m_hE50;
   handles[6] = m_hATR;
   for(int i = 0; i < 7; i++)
     {
      if(handles[i] == INVALID_HANDLE || BarsCalculated(handles[i]) < minBars)
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
bool CBBMIndicators::CopyOne(const int handle, const int buffer, const int shift, double &value)
  {
   double buf[];
   if(CopyBuffer(handle, buffer, shift, 1, buf) != 1)
      return false;
   value = buf[0];
   return (value != EMPTY_VALUE && MathIsValidNumber(value));
  }

//+------------------------------------------------------------------+
//| shift 1 = latest completed bar; shift 0 = forming bar (LIVE)     |
//+------------------------------------------------------------------+
bool CBBMIndicators::GetBar(const int shift, BBMBar &bar)
  {
   MqlRates rates[];
   if(CopyRates(m_symbol, m_tf, shift, 1, rates) != 1)
      return false;

   bar.time  = rates[0].time;
   bar.open  = rates[0].open;
   bar.high  = rates[0].high;
   bar.low   = rates[0].low;
   bar.close = rates[0].close;

   if(!CopyOne(m_hBB, BBM_BB_UPPER,  shift, bar.upper))  return false;
   if(!CopyOne(m_hBB, BBM_BB_MIDDLE, shift, bar.middle)) return false;
   if(!CopyOne(m_hBB, BBM_BB_LOWER,  shift, bar.lower))  return false;
   if(!CopyOne(m_hH5,  0, shift, bar.h5))  return false;
   if(!CopyOne(m_hH10, 0, shift, bar.h10)) return false;
   if(!CopyOne(m_hL5,  0, shift, bar.l5))  return false;
   if(!CopyOne(m_hL10, 0, shift, bar.l10)) return false;
   if(!CopyOne(m_hE50, 0, shift, bar.e50)) return false;
   if(!CopyOne(m_hATR, 0, shift, bar.atr)) return false;
   return true;
  }

#endif
