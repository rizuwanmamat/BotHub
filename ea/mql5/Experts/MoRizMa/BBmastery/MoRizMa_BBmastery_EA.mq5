//+------------------------------------------------------------------+
//| MoRizMa_BBmastery_EA.mq5                                         |
//| CT-only research baseline per MoRizMa BBmastery EA Framework v1.0|
//|                                                                  |
//| DRAFT — not compiled, not backtested. Research use on demo only. |
//| Implements: CT detector, CC/TRZ/regime diagnostics, context      |
//| filter, LIVE/FROZEN/LAST_CLOSED zones, TOUCH and REJECTION_CLOSE |
//| entries, FIXED / STRUCTURE_RR / FROZEN_OUTER_BAND exits, risk    |
//| sizing, daily lock, persistence and a candidate-level journal.   |
//| Not implemented (spec): CC/TRZ/TS entries, BEP/trailing/partial, |
//| session filter, grid/recovery/hedging.                           |
//+------------------------------------------------------------------+
#property copyright "MoRizMa / BotHub Trading"
#property version   "0.10"
#property description "MoRizMa BBmastery CT-only research EA (draft, spec v1.0)"

#include <MoRizMa/BBmastery/Defines.mqh>
#include <MoRizMa/BBmastery/Indicators.mqh>
#include <MoRizMa/BBmastery/Signals.mqh>
#include <MoRizMa/BBmastery/Context.mqh>
#include <MoRizMa/BBmastery/Candidates.mqh>
#include <MoRizMa/BBmastery/Risk.mqh>
#include <MoRizMa/BBmastery/Execution.mqh>
#include <MoRizMa/BBmastery/Exits.mqh>
#include <MoRizMa/BBmastery/Persistence.mqh>
#include <MoRizMa/BBmastery/Journal.mqh>

//--- Inputs ---------------------------------------------------------
input group "Identity"
input ulong                  InpMagic               = 26103001;   // Magic number (unique per EA/symbol)
input string                 InpRunTag              = "A";        // Run family tag (spec 19)

input group "Timeframes (initial preset H4 / H1 / M15)"
input ENUM_TIMEFRAMES        InpContextTF           = PERIOD_H4;  // Context timeframe
input ENUM_TIMEFRAMES        InpSetupTF             = PERIOD_H1;  // Setup timeframe
input ENUM_TIMEFRAMES        InpEntryTF             = PERIOD_M15; // Entry timeframe (confirmation)

input group "Indicators (U01: verify against original template)"
input int                    InpBBPeriod            = 20;
input double                 InpBBDeviation         = 2.0;
input int                    InpMAFast              = 5;          // LWMA fast (High/Low)
input int                    InpMASlow              = 10;         // LWMA slow (High/Low)
input int                    InpEMAPeriod           = 50;         // Black line EMA (Close)
input int                    InpATRPeriod           = 14;         // Diagnostic ATR (regime only)
input int                    InpRegimeK             = 5;          // Regime lookback k (diagnostic)

input group "Signals"
input ENUM_BBM_EVENT_MODE    InpEventMode           = BBM_EVENT_FIRST_TRANSITION;
input bool                   InpColourFilter        = false;      // Require C>O (bull) / C<O (bear)
input ENUM_BBM_CONTEXT_MODE  InpContextMode         = BBM_CONTEXT_MIDDLE_AND_EMA50;
input bool                   InpContextInvalidation = true;       // Cancel candidate on context loss
input int                    InpExpiryBars          = 8;          // Expiry in completed Setup bars

input group "Entry"
input ENUM_BBM_ZONE_MODE     InpZoneMode            = BBM_ZONE_LIVE;
input ENUM_BBM_ENTRY_MODEL   InpEntryModel          = BBM_ENTRY_TOUCH;
input double                 InpZoneTolerancePoints = 0.0;        // Zone tolerance (points)
input int                    InpConfirmTimeoutBars  = 3;          // REJECTION_CLOSE timeout (Entry bars)

input group "Exit (one policy per run)"
input ENUM_BBM_EXIT_POLICY   InpExitPolicy          = BBM_EXIT_FIXED;
input int                    InpFixedSLPoints       = 0;          // FIXED: SL distance (points) — REQUIRED
input int                    InpFixedTPPoints       = 0;          // FIXED: TP distance (points) — REQUIRED
input int                    InpStructureBufferPts  = 0;          // STRUCTURE: SL buffer (points)
input double                 InpRRMultiple          = 1.5;        // STRUCTURE_RR: TP = risk x RR
input int                    InpMinStopPoints       = 0;          // STRUCTURE: min stop distance (points)
input int                    InpMaxStopPoints       = 0;          // STRUCTURE: max stop distance (points) — REQUIRED
input int                    InpMinTargetPoints     = 0;          // FROZEN_OUTER_BAND: min room after costs (points)
input bool                   InpOppositeCTExit      = false;      // Exit on completed opposite CT

input group "Risk"
input ENUM_BBM_VOLUME_MODE   InpVolumeMode          = BBM_VOLUME_FIXED_LOT;
input double                 InpFixedLot            = 0.01;
input double                 InpRiskPct             = 0.25;       // EQUITY_RISK: % equity per trade
input double                 InpCommissionPerLot    = 0.0;        // Round-turn commission allowance per lot (acct ccy)
input double                 InpDailyLossLimitPct   = 2.0;        // Daily loss lock (% of day-start equity)

input group "Execution"
input int                    InpMaxSpreadPoints     = 0;          // Max spread (points) — REQUIRED, symbol-specific
input int                    InpDeviationPoints     = 10;         // Max slippage (points)
input int                    InpPendingTimeoutSec   = 30;         // Reconcile window for uncertain requests
input bool                   InpManualDisable       = false;      // Block new candidates/entries

input group "Journal & persistence"
input bool                   InpJournalEnabled      = true;
input bool                   InpJournalCommon       = true;       // Write to the terminals' Common\Files
input bool                   InpPersistState        = true;       // Persist state in terminal globals (live only)

//--- Globals --------------------------------------------------------
CBBMIndicators  g_ctx;
CBBMIndicators  g_setup;
CBBMExecution   g_exec;
CBBMDailyGuard  g_daily;
CBBMJournal     g_journal;
CBBMStore       g_store;
BBMExitParams   g_exitParams;

ENUM_BBM_STATE  g_state           = BBM_ST_IDLE;
BBMCandidate    g_cand;
bool            g_hasCand         = false;
BBMTrade        g_trade;
long            g_nextSetupId     = 1;
datetime        g_lastSetupBar    = 0;
datetime        g_lastEntryBar    = 0;
double          g_prevBid         = 0.0;
bool            g_dataReady       = false;
bool            g_candLog         = false;   // candidate snapshot belongs on journal rows
bool            g_flushPending    = false;
bool            g_protectionLock  = false;
bool            g_prevBullCC      = false;
bool            g_prevBearCC      = false;
bool            g_prevBuyWarn     = false;
bool            g_prevSellWarn    = false;
string          g_runId           = "";
string          g_paramHash       = "";
int             g_minBars         = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string StateName(const ENUM_BBM_STATE s)
  {
   switch(s)
     {
      case BBM_ST_IDLE:          return "IDLE";
      case BBM_ST_WAIT_RETEST:   return "WAIT_RETEST";
      case BBM_ST_WAIT_CONFIRM:  return "WAIT_CONFIRM";
      case BBM_ST_ORDER_PENDING: return "ORDER_PENDING";
      case BBM_ST_POSITION_OPEN: return "POSITION_OPEN";
      case BBM_ST_CLOSE_PENDING: return "CLOSE_PENDING";
      case BBM_ST_LOCKED:        return "LOCKED";
     }
   return "UNKNOWN";
  }

string TfName(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return s;
  }

bool Locked(void)
  {
   return (g_daily.locked || g_protectionLock || g_state == BBM_ST_LOCKED);
  }

void SetState(const ENUM_BBM_STATE s)
  {
   if(s == g_state)
      return;
   PrintFormat("BBM: state %s -> %s", StateName(g_state), StateName(s));
   g_state = s;
   g_flushPending = true;
  }

string ParamString(void)
  {
   return StringFormat("%s|%s|%s|%d|%.2f|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%.2f|%d|%d|%d|%d|%d|%.2f|%d|%d|%d|%d|%d|%.4f|%.4f|%.2f|%.2f|%d|%d",
                       TfName(InpContextTF), TfName(InpSetupTF), TfName(InpEntryTF),
                       InpBBPeriod, InpBBDeviation, InpMAFast, InpMASlow, InpEMAPeriod,
                       (int)InpEventMode, (int)InpColourFilter, (int)InpContextMode,
                       (int)InpContextInvalidation, InpExpiryBars, (int)InpZoneMode,
                       (int)InpEntryModel, InpZoneTolerancePoints, InpConfirmTimeoutBars,
                       (int)InpExitPolicy, InpFixedSLPoints, InpFixedTPPoints,
                       InpStructureBufferPts, InpRRMultiple, InpMinStopPoints,
                       InpMaxStopPoints, InpMinTargetPoints, (int)InpOppositeCTExit,
                       (int)InpVolumeMode, InpFixedLot, InpRiskPct, InpCommissionPerLot,
                       InpDailyLossLimitPct, InpMaxSpreadPoints, InpDeviationPoints);
  }

//+------------------------------------------------------------------+
//| Journal row: candidate snapshot + trade fields + decision        |
//+------------------------------------------------------------------+
void Journal(const string event, const string decision, const string reason, const string note,
             const string exitFields = ",,,,,,,,,,,,")
  {
   if(!InpJournalEnabled)
      return;

   int    dg     = _Digits;
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long   spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   string tz     = StringFormat("UTC%+.1f", (double)(TimeTradeServer() - TimeGMT()) / 3600.0);

   string c = "";
   if(g_candLog)
     {
      double zlo = 0.0, zhi = 0.0;
      BBM_ZoneFromBar(g_cand.dir, g_cand.sig, zlo, zhi);
      string filt = StringFormat("ctx_mode=%d;ctx_ok=%d;colour=%d", (int)InpContextMode,
                                 (int)BBM_ContextPermits(g_cand.dir, g_cand.ctx_dir, InpContextMode),
                                 (int)InpColourFilter);
      c = StringFormat("%I64d,%s,%s,%d,%d,%s,%s,%s,",
                       g_cand.id, g_cand.origin, BBM_T(g_cand.signal_time), g_cand.dir, g_cand.ctx_dir,
                       TfName(InpContextTF), TfName(InpSetupTF), TfName(InpEntryTF));
      c += StringFormat("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,",
                        BBM_D(g_cand.sig.open, dg), BBM_D(g_cand.sig.high, dg), BBM_D(g_cand.sig.low, dg),
                        BBM_D(g_cand.sig.close, dg), BBM_D(g_cand.sig.h5, dg), BBM_D(g_cand.sig.h10, dg),
                        BBM_D(g_cand.sig.l5, dg), BBM_D(g_cand.sig.l10, dg), BBM_D(g_cand.sig.upper, dg),
                        BBM_D(g_cand.sig.middle, dg), BBM_D(g_cand.sig.lower, dg), BBM_D(g_cand.sig.e50, dg),
                        (int)g_cand.cc_coexist);
      c += StringFormat("%s,%s,%s,%s,%s,%s,%s,",
                        EnumToString(InpZoneMode), BBM_D(zlo, dg), BBM_D(zhi, dg),
                        (g_cand.touch_time > 0 ? BBM_D(g_cand.touch_lo, dg) : ""),
                        (g_cand.touch_time > 0 ? BBM_D(g_cand.touch_hi, dg) : ""),
                        (g_cand.touch_time > 0 ? BBM_D(g_cand.touch_price, dg) : ""),
                        g_cand.touch_kind);
      c += StringFormat("%s,%s,%I64d,", BBM_D(bid, dg), BBM_D(ask, dg), spread);
      c += StringFormat("%s,%s,%s,%s,",
                        BBM_D(g_cand.regime.width, dg),
                        (g_cand.regime.valid ? BBM_D(g_cand.regime.norm_width, 4) : ""),
                        (g_cand.regime.valid ? BBM_D(g_cand.regime.middle_slope, 4) : ""),
                        (g_cand.regime.valid ? BBM_D(g_cand.regime.width_change, 4) : ""));
      c += StringFormat("%d,false,%s,", g_cand.bars_since, filt);
     }
   else
     {
      c = StringFormat(",,,,,%s,%s,%s,", TfName(InpContextTF), TfName(InpSetupTF), TfName(InpEntryTF));
      c += ",,,,,,,,,,,,,";
      c += StringFormat("%s,,,,,,,", EnumToString(InpZoneMode));
      c += StringFormat("%s,%s,%I64d,", BBM_D(bid, dg), BBM_D(ask, dg), spread);
      c += ",,,,";
      c += ",false,,";
     }

   string t = StringFormat("%s,%s,%I64u,%I64u,%u,%s,%s,%s,%s,%s,",
                           decision, reason,
                           g_trade.order_ticket, g_trade.deal_id, g_exec.last_retcode,
                           (g_trade.fill > 0 ? BBM_D(g_trade.fill, dg) : ""),
                           (g_trade.sl > 0 ? BBM_D(g_trade.sl, dg) : ""),
                           (g_trade.tp > 0 ? BBM_D(g_trade.tp, dg) : ""),
                           (g_trade.requested_volume > 0 ? BBM_D(g_trade.requested_volume, 2) : ""),
                           (g_trade.volume > 0 ? BBM_D(g_trade.volume, 2) : ""));
   t += (g_trade.planned_risk > 0 ? BBM_D(g_trade.planned_risk, 2) : "") + ",";

   string line = StringFormat("%s,%s,%s,%s,%s,%s,%s,%s,",
                              g_runId, BBM_CODE_VERSION, g_paramHash, _Symbol,
                              BBM_Clean(AccountInfoString(ACCOUNT_COMPANY)), tz,
                              BBM_T(TimeCurrent()), event);
   line += c + t + exitFields + "," + BBM_Clean(note);
   g_journal.WriteLine(line);
  }

//+------------------------------------------------------------------+
//| Persistence                                                      |
//+------------------------------------------------------------------+
void SaveState(void)
  {
   if(!InpPersistState || MQLInfoInteger(MQL_TESTER))
      return;
   g_store.Set("state",   (double)g_state);
   g_store.Set("hascand", g_hasCand ? 1.0 : 0.0);
   g_store.Set("nextid",  (double)g_nextSetupId);
   g_store.Set("lastsb",  (double)g_lastSetupBar);
   g_store.Set("lasteb",  (double)g_lastEntryBar);
   g_store.Set("day",     (double)g_daily.day);
   g_store.Set("dayeq",   g_daily.start_equity);
   g_store.Set("daylock", g_daily.locked ? 1.0 : 0.0);
   g_store.Set("daypart", g_daily.partial ? 1.0 : 0.0);
   g_store.Set("c_id",    (double)g_cand.id);
   g_store.Set("c_dir",   (double)g_cand.dir);
   g_store.Set("c_sigt",  (double)g_cand.signal_time);
   g_store.Set("c_bars",  (double)g_cand.bars_since);
   g_store.Set("c_ctx",   (double)g_cand.ctx_dir);
   g_store.Set("c_seen",  g_cand.seen_trend_side ? 1.0 : 0.0);
   g_store.Set("c_pos",   (double)g_cand.last_pos);
   g_store.Set("c_ext",   g_cand.extreme);
   g_store.Set("c_tt",    (double)g_cand.touch_time);
   g_store.Set("c_tb",    g_cand.touch_boundary);
   g_store.Set("c_tp",    g_cand.touch_price);
   g_store.Set("c_cb",    (double)g_cand.confirm_bars);
   g_store.Set("t_pid",   (double)g_trade.position_id);
   g_store.Set("t_risk",  g_trade.planned_risk);
   g_store.Set("t_rvol",  g_trade.requested_volume);
   g_store.Set("t_ord",   (double)g_trade.order_ticket);
   if(g_flushPending)
     {
      g_store.Flush();
      g_flushPending = false;
     }
  }

void LoadState(void)
  {
   BBM_ResetCandidate(g_cand);
   ZeroMemory(g_trade);
   if(!InpPersistState || MQLInfoInteger(MQL_TESTER) || !g_store.Has("state"))
      return;

   g_state        = (ENUM_BBM_STATE)(int)g_store.Get("state", 0);
   g_hasCand      = (g_store.Get("hascand", 0) > 0.5);
   g_nextSetupId  = (long)g_store.Get("nextid", 1);
   g_lastSetupBar = (datetime)(long)g_store.Get("lastsb", 0);
   g_lastEntryBar = (datetime)(long)g_store.Get("lasteb", 0);

   g_daily.day          = (datetime)(long)g_store.Get("day", 0);
   g_daily.start_equity = g_store.Get("dayeq", 0);
   g_daily.locked       = (g_store.Get("daylock", 0) > 0.5);
   g_daily.partial      = (g_store.Get("daypart", 1) > 0.5);

   g_cand.id              = (long)g_store.Get("c_id", 0);
   g_cand.dir             = (int)g_store.Get("c_dir", 0);
   g_cand.signal_time     = (datetime)(long)g_store.Get("c_sigt", 0);
   g_cand.bars_since      = (int)g_store.Get("c_bars", 0);
   g_cand.ctx_dir         = (int)g_store.Get("c_ctx", 0);
   g_cand.seen_trend_side = (g_store.Get("c_seen", 0) > 0.5);
   g_cand.last_pos        = (int)g_store.Get("c_pos", 99);
   g_cand.extreme         = g_store.Get("c_ext", 0);
   g_cand.touch_time      = (datetime)(long)g_store.Get("c_tt", 0);
   g_cand.touch_boundary  = g_store.Get("c_tb", 0);
   g_cand.touch_price     = g_store.Get("c_tp", 0);
   g_cand.confirm_bars    = (int)g_store.Get("c_cb", 0);

   g_trade.position_id      = (long)g_store.Get("t_pid", 0);
   g_trade.planned_risk     = g_store.Get("t_risk", 0);
   g_trade.requested_volume = g_store.Get("t_rvol", 0);
   g_trade.order_ticket     = (ulong)g_store.Get("t_ord", 0);

   //--- Re-fetch the immutable signal snapshot from history
   if(g_hasCand && g_cand.signal_time > 0)
     {
      int shift = iBarShift(_Symbol, InpSetupTF, g_cand.signal_time, true);
      if(shift < 0 || !g_setup.GetBar(shift, g_cand.sig))
         PrintFormat("BBM: signal snapshot for setup %I64d not yet available", g_cand.id);
     }
   g_candLog = (g_cand.id > 0);
   PrintFormat("BBM: restored state %s, candidate=%d id=%I64d", StateName(g_state), (int)g_hasCand, g_cand.id);
  }

//+------------------------------------------------------------------+
//| Reconcile broker state with internal state (init and on demand)  |
//+------------------------------------------------------------------+
void LoadTradeFromPosition(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return;
   g_trade.active      = true;
   g_trade.ticket      = ticket;
   g_trade.position_id = PositionGetInteger(POSITION_IDENTIFIER);
   g_trade.dir         = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   g_trade.open_time   = (datetime)PositionGetInteger(POSITION_TIME);
   g_trade.fill        = PositionGetDouble(POSITION_PRICE_OPEN);
   g_trade.volume      = PositionGetDouble(POSITION_VOLUME);
   g_trade.sl          = PositionGetDouble(POSITION_SL);
   g_trade.tp          = PositionGetDouble(POSITION_TP);
   if(g_trade.planned_risk <= 0.0 && g_trade.sl > 0.0)
     {
      double lpl = 0.0;
      if(BBM_LossPerLot(_Symbol, g_trade.dir, g_trade.fill, g_trade.sl, InpCommissionPerLot, lpl))
         g_trade.planned_risk = lpl * g_trade.volume;
     }
  }

void ReconcileOnStart(void)
  {
   ulong ticket = 0;
   int owned = g_exec.OwnedPositions(ticket);
   if(owned > 1)
     {
      g_protectionLock = true;
      Journal("RECONCILE", "LOCKED", BBM_R_OWNERSHIP_CONFLICT, StringFormat("%d owned positions found; v1 allows 1", owned));
     }
   if(owned >= 1)
     {
      LoadTradeFromPosition(ticket);
      g_hasCand = false;
      g_candLog = (g_cand.id > 0);
      SetState(BBM_ST_POSITION_OPEN);
      Journal("RECONCILE", "RESUMED", "", "owned position found on start");
      return;
     }
   //--- No owned position: anything mid-flight is resolved to IDLE
   if(g_state == BBM_ST_ORDER_PENDING || g_state == BBM_ST_POSITION_OPEN || g_state == BBM_ST_CLOSE_PENDING)
     {
      Journal("RECONCILE", "CLEARED", BBM_R_UNCONFIRMED, "no owned position on start; previous state " + StateName(g_state));
      ZeroMemory(g_trade);
      g_hasCand = false;
      g_candLog = false;
      SetState(BBM_ST_IDLE);
     }
   if(g_state == BBM_ST_LOCKED && !g_daily.locked)
      SetState(BBM_ST_IDLE);
   if((g_state == BBM_ST_WAIT_RETEST || g_state == BBM_ST_WAIT_CONFIRM) && !g_hasCand)
      SetState(BBM_ST_IDLE);
  }

//+------------------------------------------------------------------+
//| Candidate lifecycle                                              |
//+------------------------------------------------------------------+
void CancelCandidate(const string reason, const string note = "")
  {
   if(!g_hasCand)
      return;
   Journal("CANCELLED", "CANCEL", reason, note);
   g_hasCand = false;
   g_candLog = false;
   if(g_state == BBM_ST_WAIT_RETEST || g_state == BBM_ST_WAIT_CONFIRM)
      SetState(BBM_ST_IDLE);
  }

//--- Consumed without an order (spec 8.1: first eligible touch consumes)
void RejectCandidate(const string reason, const string note = "")
  {
   Journal("REJECTED", "REJECT", reason, note);
   g_hasCand = false;
   g_candLog = false;
   if(g_state == BBM_ST_WAIT_RETEST || g_state == BBM_ST_WAIT_CONFIRM)
      SetState(Locked() ? BBM_ST_LOCKED : BBM_ST_IDLE);
  }

bool GetContext(int &ctxDir)
  {
   BBMBar c;
   if(!g_ctx.GetBar(1, c))   // latest COMPLETED context bar only (spec 5)
      return false;
   ctxDir = BBM_ContextDirection(c, InpContextMode);
   return true;
  }

bool CurrentZone(double &lo, double &hi)
  {
   BBMBar b;
   if(InpZoneMode == BBM_ZONE_FROZEN_SIGNAL)
     {
      if(g_cand.sig.time == 0)
         return false;
      BBM_ZoneFromBar(g_cand.dir, g_cand.sig, lo, hi);
      return true;
     }
   int shift = (InpZoneMode == BBM_ZONE_LIVE) ? 0 : 1;
   if(!g_setup.GetBar(shift, b))
      return false;
   BBM_ZoneFromBar(g_cand.dir, b, lo, hi);
   return true;
  }

//+------------------------------------------------------------------+
//| Close-out and lock                                               |
//+------------------------------------------------------------------+
void EnterLock(const string reason, const string note)
  {
   CancelCandidate(reason, note);
   ulong ticket = 0;
   if(g_exec.OwnedPositions(ticket) > 0)
     {
      if(!g_exec.CloseAllOwned())
         Journal("LOCK_CLOSE", "CLOSE_FAILED", reason, StringFormat("retcode %u %s", g_exec.last_retcode, g_exec.last_comment));
      SetState(BBM_ST_CLOSE_PENDING);
     }
   else
      SetState(BBM_ST_LOCKED);
   Journal("LOCK", "LOCKED", reason, note);
  }

//--- Read the closed position's deals and write the outcome row
void FinaliseClosed(void)
  {
   double profit = 0.0, commission = 0.0, swap = 0.0, fee = 0.0;
   double exitPrice = 0.0;
   datetime exitTime = 0;
   string exitReason = "";

   if(g_trade.position_id > 0 && HistorySelectByPosition(g_trade.position_id))
     {
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0)
            continue;
         profit     += HistoryDealGetDouble(d, DEAL_PROFIT);
         commission += HistoryDealGetDouble(d, DEAL_COMMISSION);
         swap       += HistoryDealGetDouble(d, DEAL_SWAP);
         fee        += HistoryDealGetDouble(d, DEAL_FEE);
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
           {
            exitPrice = HistoryDealGetDouble(d, DEAL_PRICE);
            exitTime  = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            ENUM_DEAL_REASON r = (ENUM_DEAL_REASON)HistoryDealGetInteger(d, DEAL_REASON);
            exitReason = EnumToString(r);
            StringReplace(exitReason, "DEAL_REASON_", "");
           }
        }
     }

   double net   = profit + commission + swap + fee;
   double netR  = (g_trade.planned_risk > 0.0) ? net / g_trade.planned_risk : 0.0;
   long   hold  = (exitTime > 0 && g_trade.open_time > 0) ? (long)(exitTime - g_trade.open_time) : 0;

   //--- exit_time,actual_exit,exit_reason,commission,swap,fee,net_profit,MAE,MFE,basis,initial_R,net_R,holding
   string ex = StringFormat("%s,%s,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%s,%.2f,%.3f,%I64d",
                            BBM_T(exitTime), BBM_D(exitPrice, _Digits), exitReason,
                            commission, swap, fee, net, g_trade.mae, g_trade.mfe,
                            "liquidation_quote_excl_fees", g_trade.planned_risk, netR, hold);
   Journal("CLOSED", "CLOSED", "", "", ex);

   ZeroMemory(g_trade);
   BBM_ResetCandidate(g_cand);
   g_candLog = false;
   SetState(Locked() ? BBM_ST_LOCKED : BBM_ST_IDLE);
  }

//+------------------------------------------------------------------+
//| Protection: reconcile SL/TP to the actual fill (spec 10.1)       |
//+------------------------------------------------------------------+
void ReconcileProtection(void)
  {
   if(!g_trade.active || g_trade.protection_ok)
      return;
   if(!PositionSelectByTicket(g_trade.ticket))
      return;

   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   double sl = 0.0, tp = 0.0;
   string reason = "";
   double keepSL = (InpExitPolicy == BBM_EXIT_FIXED) ? 0.0 : g_trade.sl;
   double band   = (InpExitPolicy == BBM_EXIT_FROZEN_OUTER_BAND) ? g_trade.tp : 0.0;

   bool ok = BBM_ComputeExit(_Symbol, g_exitParams, g_trade.dir, g_trade.fill,
                             g_cand.extreme, band, keepSL, sl, tp, reason);
   string why = "";
   if(ok && g_exec.StopsValid(g_trade.dir, sl, tp, why) && g_exec.OutsideFreeze(g_trade.dir, sl, tp))
     {
      double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(MathAbs(sl - curSL) >= tick || MathAbs(tp - curTP) >= tick)
        {
         if(g_exec.Modify(g_trade.ticket, sl, tp))
           {
            g_trade.sl = sl;
            g_trade.tp = tp;
            curSL = sl;
            curTP = tp;
           }
        }
     }

   //--- Keep the provisional levels if reconciliation was not possible,
   //--- but never leave a filled position without a stop.
   if(curSL <= 0.0)
     {
      Journal("PROTECTION", "CLOSE", BBM_R_PROTECTION_FAILURE, StringFormat("no SL on position; retcode %u", g_exec.last_retcode));
      g_exec.Close(g_trade.ticket);
      g_protectionLock = true;
      SetState(BBM_ST_CLOSE_PENDING);
      return;
     }
   g_trade.sl = curSL;
   g_trade.tp = curTP;
   g_trade.protection_ok = true;
   Journal("PROTECTED", "PROTECTED", ok ? "" : reason, "");
  }

//--- Confirmed fill: record actual price/volume and reconcile protection
void OnFillConfirmed(const ulong ticket)
  {
   double reqSL = g_trade.sl, reqTP = g_trade.tp;
   LoadTradeFromPosition(ticket);
   if(g_trade.sl <= 0.0) g_trade.sl = reqSL;
   if(g_trade.tp <= 0.0) g_trade.tp = reqTP;
   g_trade.mae = 0.0;
   g_trade.mfe = 0.0;
   SetState(BBM_ST_POSITION_OPEN);

   string note = "";
   if(g_trade.requested_volume > 0.0 && g_trade.volume < g_trade.requested_volume - 1e-9)
      note = StringFormat("partial fill: residual %.2f not topped up", g_trade.requested_volume - g_trade.volume);
   Journal("FILLED", "FILLED", "", note);
   ReconcileProtection();
  }

//+------------------------------------------------------------------+
//| Entry attempt — consumes the candidate whatever the outcome      |
//+------------------------------------------------------------------+
void AttemptEntry(const MqlTick &tick, const string trigger)
  {
   int dir = g_cand.dir;

   //--- 1. candidate / context
   int ctxDir = 0;
   if(!GetContext(ctxDir)) { RejectCandidate(BBM_R_DATA_NOT_READY, trigger); return; }
   if(!BBM_ContextPermits(dir, ctxDir, InpContextMode))
     { RejectCandidate(BBM_R_CONTEXT_CONFLICT, trigger + StringFormat(" ctx=%d", ctxDir)); return; }

   //--- 2. exposure, lock, spread, market
   ulong owned = 0;
   if(Locked())                                  { RejectCandidate(BBM_R_DAILY_LOCK, trigger); return; }
   if(InpManualDisable)                          { RejectCandidate(BBM_R_MANUAL_DISABLE, trigger); return; }
   if(g_exec.OwnedPositions(owned) > 0 || g_exec.OwnedOrders() > 0)
                                                 { RejectCandidate(BBM_R_EXPOSURE_ACTIVE, trigger); return; }
   if(g_exec.OwnershipConflict())                { RejectCandidate(BBM_R_OWNERSHIP_CONFLICT, trigger); return; }
   if(!g_exec.MarketOpenFor(dir))                { RejectCandidate(BBM_R_MARKET_CLOSED, trigger); return; }
   double spreadPts = (tick.ask - tick.bid) / _Point;
   if(spreadPts > InpMaxSpreadPoints)
     { RejectCandidate(BBM_R_SPREAD_HIGH, trigger + StringFormat(" spread=%.1f", spreadPts)); return; }

   //--- 3. intended entry from executable quote
   double entry = (dir > 0) ? tick.ask : tick.bid;

   //--- 4. SL / TP / volume
   double band = 0.0;
   if(InpExitPolicy == BBM_EXIT_FROZEN_OUTER_BAND)
     {
      BBMBar b1;
      if(!g_setup.GetBar(1, b1)) { RejectCandidate(BBM_R_DATA_NOT_READY, trigger); return; }
      band = (dir > 0) ? b1.upper : b1.lower;
     }
   double sl = 0.0, tp = 0.0, vol = 0.0, risk = 0.0;
   string reason = "";
   if(!BBM_ComputeExit(_Symbol, g_exitParams, dir, entry, g_cand.extreme, band, 0.0, sl, tp, reason))
     { RejectCandidate(reason, trigger); return; }
   if(!g_exec.StopsValid(dir, sl, tp, reason))
     { RejectCandidate(reason, trigger + " stops level"); return; }
   if(!BBM_ComputeVolume(_Symbol, dir, entry, sl, InpVolumeMode, InpFixedLot, InpRiskPct,
                         InpCommissionPerLot, vol, risk, reason))
     { RejectCandidate(reason, trigger); return; }

   //--- 5. margin
   if(!BBM_MarginOk(_Symbol, dir, vol, entry))
     { RejectCandidate(BBM_R_MARGIN_LOW, trigger); return; }

   //--- 6. one market request
   ZeroMemory(g_trade);
   g_trade.dir              = dir;
   g_trade.requested_volume = vol;
   g_trade.planned_risk     = risk;
   g_trade.sl               = sl;
   g_trade.tp               = tp;
   g_trade.pending_since    = TimeCurrent();
   SetState(BBM_ST_ORDER_PENDING);
   SaveState();

   string comment = StringFormat("BBM %s #%I64d", (dir > 0 ? "B" : "S"), g_cand.id);
   bool sent = g_exec.Open(dir, vol, entry, sl, tp, comment);
   g_trade.order_ticket = g_exec.last_order;
   g_trade.deal_id      = g_exec.last_deal;
   g_hasCand = false;   // consumed

   if(sent)
     {
      ulong ticket = 0;
      if(g_exec.OwnedPositions(ticket) > 0)
         OnFillConfirmed(ticket);
      else
         Journal("SUBMITTED", "PENDING", "", trigger + " awaiting position");
      return;
     }

   if(CBBMExecution::IsUncertain(g_exec.last_retcode))
     {
      Journal("SUBMITTED", "UNCERTAIN", BBM_R_UNCONFIRMED,
              StringFormat("%s retcode %u %s", trigger, g_exec.last_retcode, g_exec.last_comment));
      return;   // stay ORDER_PENDING; ReconcilePending decides
     }

   string why = (g_exec.last_retcode == TRADE_RETCODE_MARKET_CLOSED) ? BBM_R_MARKET_CLOSED :
                (g_exec.last_retcode == TRADE_RETCODE_NO_MONEY)      ? BBM_R_MARGIN_LOW    :
                BBM_R_BROKER_REJECT;
   Journal("REJECTED", "REJECT", why, StringFormat("%s retcode %u %s", trigger, g_exec.last_retcode, g_exec.last_comment));
   ZeroMemory(g_trade);
   g_candLog = false;
   SetState(Locked() ? BBM_ST_LOCKED : BBM_ST_IDLE);
  }

//--- Uncertain submissions: wait for a position; never resend blindly
void ReconcilePending(void)
  {
   if(g_state != BBM_ST_ORDER_PENDING)
      return;
   ulong ticket = 0;
   if(g_exec.OwnedPositions(ticket) > 0)
     {
      OnFillConfirmed(ticket);
      return;
     }
   if(g_exec.OwnedOrders() > 0)
      return;
   if(TimeCurrent() - g_trade.pending_since >= InpPendingTimeoutSec)
     {
      Journal("RECONCILE", "CLEARED", BBM_R_UNCONFIRMED, "no position or order after timeout");
      ZeroMemory(g_trade);
      g_candLog = false;
      SetState(Locked() ? BBM_ST_LOCKED : BBM_ST_IDLE);
     }
  }

//+------------------------------------------------------------------+
//| Open-position management: MAE/MFE, closure detection             |
//+------------------------------------------------------------------+
void ManagePosition(const MqlTick &tick)
  {
   if(g_state != BBM_ST_POSITION_OPEN && g_state != BBM_ST_CLOSE_PENDING)
      return;

   if(!PositionSelectByTicket(g_trade.ticket))
     {
      FinaliseClosed();   // closed by SL/TP/manual — process, never send a second close
      return;
     }

   //--- MAE/MFE at executable liquidation quotes, fees excluded (spec 17)
   double liq = (g_trade.dir > 0) ? tick.bid : tick.ask;
   ENUM_ORDER_TYPE type = (g_trade.dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double pl = 0.0;
   if(OrderCalcProfit(type, _Symbol, g_trade.volume, g_trade.fill, liq, pl))
     {
      g_trade.mae = MathMin(g_trade.mae, pl);
      g_trade.mfe = MathMax(g_trade.mfe, pl);
     }

   if(g_state == BBM_ST_POSITION_OPEN)
      ReconcileProtection();
  }

//+------------------------------------------------------------------+
//| New completed Setup bar: invalidate/expire FIRST, then arm       |
//+------------------------------------------------------------------+
void OnNewSetupBar(void)
  {
   BBMBar b1, b2, b1k;
   if(!g_setup.GetBar(1, b1) || !g_setup.GetBar(2, b2))
     {
      if(g_hasCand)
         Journal("DATA", "SKIP", BBM_R_DATA_NOT_READY, "setup bars unavailable");
      return;
     }
   bool bull1 = BBM_BullCandidate(b1, InpColourFilter);
   bool bear1 = BBM_BearCandidate(b1, InpColourFilter);
   bool bull2 = BBM_BullCandidate(b2, InpColourFilter);
   bool bear2 = BBM_BearCandidate(b2, InpColourFilter);
   int  ctxDir = 0;
   bool ctxOk  = GetContext(ctxDir);

   //--- a) expiry / invalidation of the active candidate
   if(g_hasCand && (g_state == BBM_ST_WAIT_RETEST || g_state == BBM_ST_WAIT_CONFIRM))
     {
      g_cand.bars_since++;
      if(g_cand.bars_since >= InpExpiryBars)
         CancelCandidate(BBM_R_EXPIRED);
      else if((g_cand.dir > 0 && bear1) || (g_cand.dir < 0 && bull1))
         CancelCandidate(BBM_R_OPPOSITE_CT);
      else if(InpContextInvalidation && InpContextMode != BBM_CONTEXT_OFF &&
              (!ctxOk || !BBM_ContextPermits(g_cand.dir, ctxDir, InpContextMode)))
         CancelCandidate(BBM_R_CONTEXT_CONFLICT, StringFormat("ctx=%d", ctxDir));
      else if(g_cand.dir > 0)
         g_cand.extreme = MathMin(g_cand.extreme, b1.low);
      else
         g_cand.extreme = MathMax(g_cand.extreme, b1.high);
     }

   //--- b) optional opposite-CT exit; hard SL stays in place
   if(InpOppositeCTExit && g_state == BBM_ST_POSITION_OPEN &&
      ((g_trade.dir > 0 && bear1) || (g_trade.dir < 0 && bull1)))
     {
      Journal("EXIT_SIGNAL", "CLOSE", "OPPOSITE_CT_EXIT", "");
      if(g_exec.Close(g_trade.ticket))
         SetState(BBM_ST_CLOSE_PENDING);
      else
         Journal("EXIT_SIGNAL", "CLOSE_FAILED", BBM_R_BROKER_REJECT, StringFormat("retcode %u", g_exec.last_retcode));
     }

   //--- c) diagnostics: CC and TRZ warning transitions (never traded in v1)
   bool bullCC = BBM_BullCC(b1), bearCC = BBM_BearCC(b1);
   bool buyW   = BBM_BuyWarning(b1), sellW = BBM_SellWarning(b1);
   if(bullCC && !g_prevBullCC) Journal("CC_DIAG", "DIAGNOSTIC", "", "bull CC " + BBM_T(b1.time));
   if(bearCC && !g_prevBearCC) Journal("CC_DIAG", "DIAGNOSTIC", "", "bear CC " + BBM_T(b1.time));
   if(buyW && !g_prevBuyWarn)  Journal("TRZ_DIAG", "DIAGNOSTIC", "", "buy warning " + BBM_T(b1.time));
   if(sellW && !g_prevSellWarn) Journal("TRZ_DIAG", "DIAGNOSTIC", "", "sell warning " + BBM_T(b1.time));
   g_prevBullCC = bullCC; g_prevBearCC = bearCC; g_prevBuyWarn = buyW; g_prevSellWarn = sellW;

   //--- d) arm a new CT candidate
   bool newBull = BBM_IsEvent(bull1, bull2, InpEventMode);
   bool newBear = BBM_IsEvent(bear1, bear2, InpEventMode);
   if(!newBull && !newBear)
      return;

   int dir = newBull ? 1 : -1;

   //--- Same-direction events never refresh an existing candidate (spec 6.2)
   if(g_hasCand)
     {
      PrintFormat("BBM: CT event %d at %s not armed: %s (candidate %I64d)",
                  dir, BBM_T(b1.time), BBM_R_CANDIDATE_ACTIVE, g_cand.id);
      return;
     }

   BBMCandidate saved    = g_cand;   // keep trade-linked snapshot intact for journal rows
   bool         savedLog = g_candLog;
   BBM_ResetCandidate(g_cand);
   g_cand.id          = g_nextSetupId++;
   g_cand.dir         = dir;
   g_cand.signal_time = b1.time;
   g_cand.sig         = b1;
   g_cand.ctx_dir     = ctxDir;
   g_cand.cc_coexist  = (dir > 0) ? bullCC : bearCC;
   g_cand.extreme     = (dir > 0) ? b1.low : b1.high;
   if(g_setup.GetBar(1 + InpRegimeK, b1k))
      BBM_ComputeRegime(b1, b1k, InpRegimeK, g_cand.regime);
   g_candLog = true;

   string reason = "";
   if(g_state == BBM_ST_POSITION_OPEN || g_state == BBM_ST_ORDER_PENDING || g_state == BBM_ST_CLOSE_PENDING)
      reason = BBM_R_EXPOSURE_ACTIVE;
   else if(Locked())
      reason = BBM_R_DAILY_LOCK;
   else if(InpManualDisable)
      reason = BBM_R_MANUAL_DISABLE;
   else if(!ctxOk)
      reason = BBM_R_DATA_NOT_READY;
   else if(!BBM_ContextPermits(dir, ctxDir, InpContextMode))
      reason = BBM_R_CONTEXT_CONFLICT;
   else if(g_exec.OwnershipConflict())
      reason = BBM_R_OWNERSHIP_CONFLICT;

   if(reason != "")
     {
      Journal("NOT_ARMED", "REJECT", reason, "");
      if(g_state == BBM_ST_POSITION_OPEN || g_state == BBM_ST_ORDER_PENDING || g_state == BBM_ST_CLOSE_PENDING)
        {
         g_cand    = saved;
         g_candLog = savedLog;
        }
      else
         g_candLog = false;
      return;
     }

   g_hasCand = true;
   SetState(BBM_ST_WAIT_RETEST);
   Journal("ARMED", "ARM", "", "");
  }

//+------------------------------------------------------------------+
//| New Entry bar: REJECTION_CLOSE confirmation (spec 8.2)           |
//+------------------------------------------------------------------+
void OnNewEntryBar(const MqlTick &tick)
  {
   if(g_state != BBM_ST_WAIT_CONFIRM || !g_hasCand)
      return;
   MqlRates r[];
   if(CopyRates(_Symbol, InpEntryTF, 1, 1, r) != 1)
      return;
   datetime closeTime = r[0].time + PeriodSeconds(InpEntryTF);
   if(closeTime <= g_cand.touch_time)
      return;

   g_cand.confirm_bars++;
   bool confirmed = (g_cand.dir > 0) ? (r[0].close > g_cand.touch_boundary)
                                     : (r[0].close < g_cand.touch_boundary);
   if(confirmed)
      AttemptEntry(tick, "REJECTION_CLOSE");
   else if(g_cand.confirm_bars >= InpConfirmTimeoutBars)
      CancelCandidate(BBM_R_CONFIRM_TIMEOUT, StringFormat("%d entry bars", g_cand.confirm_bars));
  }

//+------------------------------------------------------------------+
//| Tick retest against the Setup-timeframe zone (spec 7, 8)         |
//+------------------------------------------------------------------+
void ProcessRetest(const MqlTick &tick)
  {
   double lo = 0.0, hi = 0.0;
   if(!CurrentZone(lo, hi))
      return;

   //--- Causal extreme update for structural stops (observed Bid, spec 10.2)
   if(g_cand.dir > 0) g_cand.extreme = MathMin(g_cand.extreme, tick.bid);
   else               g_cand.extreme = MathMax(g_cand.extreme, tick.bid);

   double tol = InpZoneTolerancePoints * _Point;
   ENUM_BBM_RETEST res = BBM_UpdateRetest(g_cand, tick.bid, g_prevBid, lo, hi, tol);

   if(res == BBM_RETEST_GAP)
     {
      Journal("GAP", "SKIP", BBM_R_GAP_SKIPPED,
              StringFormat("bid %s jumped through [%s,%s]", BBM_D(tick.bid, _Digits), BBM_D(lo, _Digits), BBM_D(hi, _Digits)));
      return;
     }
   if(res != BBM_RETEST_TOUCH)
      return;

   g_cand.touch_time  = TimeCurrent();
   g_cand.touch_price = tick.bid;
   g_cand.touch_lo    = lo;
   g_cand.touch_hi    = hi;

   if(InpEntryModel == BBM_ENTRY_TOUCH)
     {
      Journal("TOUCH", "TOUCH", BBM_R_TOUCH_CONSUMED, "");
      AttemptEntry(tick, "TOUCH");
      return;
     }

   //--- REJECTION_CLOSE: freeze the boundary at touch so confirmation cannot move
   g_cand.touch_boundary = (g_cand.dir > 0) ? hi : lo;
   g_cand.confirm_bars   = 0;
   SetState(BBM_ST_WAIT_CONFIRM);
   Journal("TOUCH", "WAIT_CONFIRM", "", StringFormat("boundary %s", BBM_D(g_cand.touch_boundary, _Digits)));
  }

//+------------------------------------------------------------------+
//| Daily protection                                                 |
//+------------------------------------------------------------------+
void CheckDaily(void)
  {
   if(g_daily.Roll())
     {
      Journal("DAY_ROLL", "RESET", "", StringFormat("day-start equity %.2f", g_daily.start_equity));
      if(g_state == BBM_ST_LOCKED && !g_protectionLock)
         SetState(BBM_ST_IDLE);
     }
   if(g_daily.CheckBreach(InpDailyLossLimitPct))
      EnterLock(BBM_R_DAILY_LOCK, StringFormat("equity %.2f vs day-start %.2f%s",
                AccountInfoDouble(ACCOUNT_EQUITY), g_daily.start_equity,
                g_daily.partial ? " (partial-day baseline)" : ""));
  }

//+------------------------------------------------------------------+
//| Input validation (spec 10.1, 11, 12, U10)                        |
//+------------------------------------------------------------------+
bool ValidateInputs(void)
  {
   bool ok = true;
   if(InpMaxSpreadPoints <= 0)    { Print("BBM: InpMaxSpreadPoints is required (symbol-specific)."); ok = false; }
   if(InpExpiryBars < 1)          { Print("BBM: InpExpiryBars must be >= 1."); ok = false; }
   if(InpBBPeriod < 2 || InpMAFast < 1 || InpMASlow < 1 || InpEMAPeriod < 1 || InpBBDeviation <= 0.0)
     { Print("BBM: invalid indicator settings."); ok = false; }
   if(InpExitPolicy == BBM_EXIT_FIXED && (InpFixedSLPoints <= 0 || InpFixedTPPoints <= 0))
     { Print("BBM: FIXED exit requires InpFixedSLPoints and InpFixedTPPoints > 0."); ok = false; }
   if(InpExitPolicy != BBM_EXIT_FIXED && InpMaxStopPoints <= 0)
     { Print("BBM: structural exits require InpMaxStopPoints > 0."); ok = false; }
   if(InpExitPolicy == BBM_EXIT_STRUCTURE_RR && InpRRMultiple <= 0.0)
     { Print("BBM: InpRRMultiple must be > 0."); ok = false; }
   if(InpVolumeMode == BBM_VOLUME_FIXED_LOT && InpFixedLot <= 0.0)
     { Print("BBM: InpFixedLot must be > 0."); ok = false; }
   if(InpVolumeMode == BBM_VOLUME_EQUITY_RISK && (InpRiskPct <= 0.0 || InpRiskPct > 5.0))
     { Print("BBM: InpRiskPct must be in (0, 5]."); ok = false; }
   if(InpDailyLossLimitPct <= 0.0)
     { Print("BBM: InpDailyLossLimitPct must be > 0."); ok = false; }
   if(InpEntryModel == BBM_ENTRY_REJECTION_CLOSE && InpConfirmTimeoutBars < 1)
     { Print("BBM: InpConfirmTimeoutBars must be >= 1."); ok = false; }
   if(InpZoneTolerancePoints < 0.0)
     { Print("BBM: InpZoneTolerancePoints must be >= 0."); ok = false; }
   if(PeriodSeconds(InpContextTF) < PeriodSeconds(InpSetupTF) || PeriodSeconds(InpSetupTF) < PeriodSeconds(InpEntryTF))
      Print("BBM: warning — expected Context >= Setup >= Entry timeframe.");
   return ok;
  }

//+------------------------------------------------------------------+
//| Expert initialisation                                            |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_exitParams.policy                  = InpExitPolicy;
   g_exitParams.fixed_sl_points         = InpFixedSLPoints;
   g_exitParams.fixed_tp_points         = InpFixedTPPoints;
   g_exitParams.structure_buffer_points = InpStructureBufferPts;
   g_exitParams.rr_multiple             = InpRRMultiple;
   g_exitParams.min_stop_points         = InpMinStopPoints;
   g_exitParams.max_stop_points         = InpMaxStopPoints;
   g_exitParams.min_target_points       = InpMinTargetPoints;

   if(!g_ctx.Init(_Symbol, InpContextTF, InpBBPeriod, InpBBDeviation, InpMAFast, InpMASlow, InpEMAPeriod, InpATRPeriod))
      return INIT_FAILED;
   if(!g_setup.Init(_Symbol, InpSetupTF, InpBBPeriod, InpBBDeviation, InpMAFast, InpMASlow, InpEMAPeriod, InpATRPeriod))
      return INIT_FAILED;
   if(!g_exec.Init(_Symbol, InpMagic, (ulong)InpDeviationPoints))
      Print("BBM: warning — could not resolve filling mode from symbol; CTrade default used.");

   g_minBars   = MathMax(MathMax(InpBBPeriod, InpEMAPeriod), MathMax(InpMASlow, InpATRPeriod)) + InpRegimeK + 5;
   g_paramHash = BBM_Hash(ParamString());
   g_runId     = StringFormat("%s_%s_%I64d", InpRunTag, g_paramHash, (long)TimeLocal());

   if(InpJournalEnabled)
     {
      string file = StringFormat("MoRizMa_BBmastery_%s_%I64u.csv", _Symbol, InpMagic);
      g_journal.Open(file, InpJournalCommon);
     }

   g_store.Init(InpMagic, _Symbol);
   LoadState();
   datetime anchorDay = g_daily.day;
   g_daily.Roll();
   if(g_daily.day != anchorDay)
      g_daily.partial = true;   // anchored mid-day without that day's history
   ReconcileOnStart();

   Journal("INIT", "START", "", StringFormat("params=%s netting=%d state=%s",
           ParamString(), (int)g_exec.IsNetting(), StateName(g_state)));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialisation                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_flushPending = true;
   SaveState();
   Journal("DEINIT", "STOP", "", StringFormat("reason %d state %s", reason, StateName(g_state)));
   g_journal.Close();
   g_ctx.Release();
   g_setup.Release();
  }

//+------------------------------------------------------------------+
//| Tick loop (spec 14)                                              |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;

   //--- reconcile transactions and daily protection
   ReconcilePending();
   CheckDaily();

   //--- manage existing position
   ManagePosition(tick);

   //--- missing data: no new entries (server-side SL/TP still protects)
   bool ready = g_setup.Ready(g_minBars) && g_ctx.Ready(g_minBars);
   if(!ready)
     {
      if(g_dataReady)
         Journal("DATA", "PAUSE", BBM_R_DATA_NOT_READY, "");
      g_dataReady = false;
      g_prevBid = tick.bid;
      return;
     }
   g_dataReady = true;

   //--- completed-bar invalidation/expiry BEFORE this tick's touch (spec 9)
   datetime sb = iTime(_Symbol, InpSetupTF, 0);
   if(sb > 0 && sb != g_lastSetupBar)
     {
      g_lastSetupBar = sb;
      OnNewSetupBar();
     }
   datetime eb = iTime(_Symbol, InpEntryTF, 0);
   if(eb > 0 && eb != g_lastEntryBar)
     {
      g_lastEntryBar = eb;
      OnNewEntryBar(tick);
     }

   if(Locked() || InpManualDisable)
     {
      if(g_hasCand)
         CancelCandidate(Locked() ? BBM_R_DAILY_LOCK : BBM_R_MANUAL_DISABLE);
     }
   else if(g_state == BBM_ST_WAIT_RETEST && g_hasCand)
      ProcessRetest(tick);

   g_prevBid = tick.bid;
   SaveState();
  }

//+------------------------------------------------------------------+
//| Authoritative fills / closures and balance operations            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(dtype == DEAL_TYPE_BALANCE || dtype == DEAL_TYPE_CREDIT)
     {
      //--- Declared policy: day-start equity is NOT adjusted for deposits/withdrawals
      Journal("BALANCE_OP", "LOGGED", "", StringFormat("%s %.2f; daily anchor not adjusted",
              EnumToString(dtype), HistoryDealGetDouble(trans.deal, DEAL_PROFIT)));
      return;
     }

   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   bool mine = ((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == InpMagic) ||
               (g_trade.position_id > 0 && HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID) == g_trade.position_id);
   if(!mine)
      return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN && g_state == BBM_ST_ORDER_PENDING)
     {
      ulong ticket = 0;
      if(g_exec.OwnedPositions(ticket) > 0)
         OnFillConfirmed(ticket);
     }
   else if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) &&
           (g_state == BBM_ST_POSITION_OPEN || g_state == BBM_ST_CLOSE_PENDING) &&
           !PositionSelectByTicket(g_trade.ticket))
      FinaliseClosed();
   SaveState();
  }
//+------------------------------------------------------------------+
