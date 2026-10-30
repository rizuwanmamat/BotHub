//+------------------------------------------------------------------+
//| Journal.mqh                                                      |
//| Candidate-level CSV event log, including rejections (spec 17)    |
//+------------------------------------------------------------------+
#ifndef MORIZMA_BBM_JOURNAL_MQH
#define MORIZMA_BBM_JOURNAL_MQH

#include "Defines.mqh"

//--- djb2 hash for the parameter fingerprint
string BBM_Hash(const string s)
  {
   uint h = 5381;
   int  n = StringLen(s);
   for(int i = 0; i < n; i++)
      h = ((h << 5) + h) + (uint)StringGetCharacter(s, i);
   return StringFormat("%08X", h);
  }

string BBM_D(const double v, const int digits)
  {
   if(v == EMPTY_VALUE || !MathIsValidNumber(v))
      return "";
   return DoubleToString(v, digits);
  }

string BBM_T(const datetime t)
  {
   if(t <= 0)
      return "";
   return TimeToString(t, TIME_DATE | TIME_SECONDS);
  }

string BBM_Clean(const string s)
  {
   string r = s;
   StringReplace(r, ",", ";");
   StringReplace(r, "\r", " ");
   StringReplace(r, "\n", " ");
   return r;
  }

class CBBMJournal
  {
private:
   int               m_handle;

public:
                     CBBMJournal(void) : m_handle(INVALID_HANDLE) {}
                    ~CBBMJournal(void) { Close(); }

   static string     Header(void)
     {
      return "run_id,code_version,parameter_hash,symbol,broker,server_timezone,server_time,event,"
             "setup_id,setup_origin,signal_time,direction,context_direction,"
             "timeframe_context,timeframe_setup,timeframe_entry,"
             "signal_O,signal_H,signal_L,signal_C,signal_H5,signal_H10,signal_L5,signal_L10,"
             "signal_U,signal_M,signal_D,signal_EMA50,cc_coexist,"
             "zone_mode,zone_at_signal_lo,zone_at_signal_hi,zone_at_touch_lo,zone_at_touch_hi,"
             "reference_touch_price,touch_kind,bid,ask,spread_points,"
             "band_width,normalised_width,middle_slope,width_change,"
             "signal_age_bars,full_sequence_verified,filter_results,decision,rejection_reason,"
             "order_ticket,deal_id,retcode,actual_fill,initial_SL,initial_TP,requested_volume,actual_volume,"
             "planned_risk_currency,exit_time,actual_exit,exit_reason,commission,swap,fee,net_profit,"
             "MAE_currency,MFE_currency,mae_mfe_basis,initial_R,net_R,holding_seconds,note";
     }

   bool              Open(const string fileName, const bool common)
     {
      Close();
      int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
      if(common)
         flags |= FILE_COMMON;
      m_handle = FileOpen(fileName, flags);
      if(m_handle == INVALID_HANDLE)
        {
         PrintFormat("BBM: journal open failed (%s), error %d", fileName, GetLastError());
         return false;
        }
      if(FileSize(m_handle) == 0)
         FileWriteString(m_handle, Header() + "\r\n");
      FileSeek(m_handle, 0, SEEK_END);
      FileFlush(m_handle);
      return true;
     }

   void              Close(void)
     {
      if(m_handle != INVALID_HANDLE)
        {
         FileClose(m_handle);
         m_handle = INVALID_HANDLE;
        }
     }

   void              WriteLine(const string line)
     {
      if(m_handle == INVALID_HANDLE)
         return;
      FileWriteString(m_handle, line + "\r\n");
      FileFlush(m_handle);
     }
  };

#endif
