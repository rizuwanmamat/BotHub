//+------------------------------------------------------------------+
//| Persistence.mqh                                                  |
//| Terminal global-variable state store (spec 12: survive restart)  |
//+------------------------------------------------------------------+
#ifndef MORIZMA_BBM_PERSISTENCE_MQH
#define MORIZMA_BBM_PERSISTENCE_MQH

#include "Defines.mqh"

//--- Global-variable names are limited to 63 characters
class CBBMStore
  {
private:
   string            m_prefix;

public:
   void              Init(const ulong magic, const string symbol)
     {
      m_prefix = StringFormat("BBM_%I64u_%s_", magic, symbol);
      if(StringLen(m_prefix) > 48)
         m_prefix = StringSubstr(m_prefix, 0, 48);
     }

   void              Set(const string key, const double value)
     {
      GlobalVariableSet(m_prefix + key, value);
     }

   double            Get(const string key, const double fallback) const
     {
      double v = 0.0;
      if(GlobalVariableGet(m_prefix + key, v))
         return v;
      return fallback;
     }

   bool              Has(const string key) const
     {
      return GlobalVariableCheck(m_prefix + key);
     }

   void              Flush(void)
     {
      GlobalVariablesFlush();
     }
  };

#endif
