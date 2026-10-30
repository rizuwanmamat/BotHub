//+------------------------------------------------------------------+
//| Defines.mqh                                                      |
//| MoRizMa BBmastery — shared enums, structs and reason codes       |
//| Spec: research/specifications/MoRizMa_BBmastery_EA_Framework_v1.0|
//+------------------------------------------------------------------+
#ifndef MORIZMA_BBM_DEFINES_MQH
#define MORIZMA_BBM_DEFINES_MQH

#define BBM_CODE_VERSION  "0.1.0-draft"
#define BBM_SPEC_VERSION  "1.0"

//--- Spec 6.2: event versus persistent condition
enum ENUM_BBM_EVENT_MODE
  {
   BBM_EVENT_FIRST_TRANSITION     = 0, // FIRST_TRANSITION (default)
   BBM_EVENT_EVERY_QUALIFYING_BAR = 1  // EVERY_QUALIFYING_BAR (experiment)
  };

//--- Spec 6.4: context direction filter
enum ENUM_BBM_CONTEXT_MODE
  {
   BBM_CONTEXT_OFF              = 0, // OFF (unfiltered baseline)
   BBM_CONTEXT_MIDDLE_BAND_ONLY = 1, // MIDDLE_BAND_ONLY
   BBM_CONTEXT_MIDDLE_AND_EMA50 = 2  // MIDDLE_AND_EMA50 (default)
  };

//--- Spec 7: entry zone source
enum ENUM_BBM_ZONE_MODE
  {
   BBM_ZONE_LIVE          = 0, // LIVE (default)
   BBM_ZONE_FROZEN_SIGNAL = 1, // FROZEN_SIGNAL (experiment)
   BBM_ZONE_LAST_CLOSED   = 2  // LAST_CLOSED (experiment)
  };

//--- Spec 8: entry model
enum ENUM_BBM_ENTRY_MODEL
  {
   BBM_ENTRY_TOUCH           = 0, // TOUCH (default)
   BBM_ENTRY_REJECTION_CLOSE = 1  // REJECTION_CLOSE (experiment)
  };

//--- Spec 10: one exit policy per run
enum ENUM_BBM_EXIT_POLICY
  {
   BBM_EXIT_FIXED             = 0, // FIXED (entry-quality baseline)
   BBM_EXIT_STRUCTURE_RR      = 1, // STRUCTURE_RR (experiment)
   BBM_EXIT_FROZEN_OUTER_BAND = 2  // FROZEN_OUTER_BAND (experiment)
  };

//--- Spec 11: volume mode
enum ENUM_BBM_VOLUME_MODE
  {
   BBM_VOLUME_FIXED_LOT   = 0, // FIXED_LOT (comparisons)
   BBM_VOLUME_EQUITY_RISK = 1  // EQUITY_RISK (normalised)
  };

//--- Spec 13: state machine
enum ENUM_BBM_STATE
  {
   BBM_ST_IDLE          = 0,
   BBM_ST_WAIT_RETEST   = 1,
   BBM_ST_WAIT_CONFIRM  = 2,
   BBM_ST_ORDER_PENDING = 3,
   BBM_ST_POSITION_OPEN = 4,
   BBM_ST_CLOSE_PENDING = 5,
   BBM_ST_LOCKED        = 6
  };

//--- Spec 17: reason codes (plus a few implementation-specific ones)
#define BBM_R_CONTEXT_CONFLICT   "CONTEXT_CONFLICT"
#define BBM_R_EXPIRED            "EXPIRED"
#define BBM_R_OPPOSITE_CT        "OPPOSITE_CT"
#define BBM_R_SPREAD_HIGH        "SPREAD_HIGH"
#define BBM_R_GAP_SKIPPED        "GAP_SKIPPED"
#define BBM_R_STOP_INVALID       "STOP_INVALID"
#define BBM_R_TARGET_INVALID     "TARGET_INVALID"
#define BBM_R_VOLUME_BELOW_MIN   "VOLUME_BELOW_MIN"
#define BBM_R_MARGIN_LOW         "MARGIN_LOW"
#define BBM_R_OWNERSHIP_CONFLICT "OWNERSHIP_CONFLICT"
#define BBM_R_DAILY_LOCK         "DAILY_LOCK"
#define BBM_R_DATA_NOT_READY     "DATA_NOT_READY"
#define BBM_R_BROKER_REJECT      "BROKER_REJECT"
#define BBM_R_TOUCH_CONSUMED     "TOUCH_CONSUMED"
#define BBM_R_PROTECTION_FAILURE "PROTECTION_FAILURE"
#define BBM_R_CONFIRM_TIMEOUT    "CONFIRM_TIMEOUT"
#define BBM_R_CANDIDATE_ACTIVE   "CANDIDATE_ACTIVE"
#define BBM_R_EXPOSURE_ACTIVE    "EXPOSURE_ACTIVE"
#define BBM_R_MARKET_CLOSED      "MARKET_CLOSED"
#define BBM_R_MANUAL_DISABLE     "MANUAL_DISABLE"
#define BBM_R_UNCONFIRMED        "REQUEST_UNCONFIRMED"

//--- One timeframe's completed (or forming, shift 0) bar with indicator values
struct BBMBar
  {
   datetime          time;     // bar open time
   double            open;
   double            high;
   double            low;
   double            close;
   double            upper;    // U
   double            middle;   // M
   double            lower;    // D
   double            h5;       // LWMA5 High
   double            h10;      // LWMA10 High
   double            l5;       // LWMA5 Low
   double            l10;      // LWMA10 Low
   double            e50;      // EMA50 Close
   double            atr;      // diagnostic only (spec 16)
  };

//--- Spec 16: band-regime diagnostics (never used as a filter in v1)
struct BBMRegime
  {
   bool              valid;
   double            width;
   double            norm_width;
   double            middle_slope;
   double            width_change;
  };

//--- An armed setup candidate (spec 6, 7, 9)
struct BBMCandidate
  {
   long              id;
   int               dir;              // +1 buy, -1 sell
   string            origin;           // "CT" in v1
   datetime          signal_time;      // signal bar open time (Setup TF)
   int               bars_since;       // completed Setup bars after the signal bar
   int               ctx_dir;          // context direction at signal
   bool              cc_coexist;       // CC on the same signal candle
   BBMBar            sig;              // immutable signal snapshot
   BBMRegime         regime;           // regime snapshot at signal
   bool              seen_trend_side;  // price observed beyond zone on the trend side
   int               last_pos;         // last relative position: +1 above, 0 in, -1 below, 99 unknown
   double            extreme;          // causal low (buy) / high (sell) since signal — STRUCTURE_RR
   datetime          touch_time;
   double            touch_price;
   double            touch_lo;
   double            touch_hi;
   double            touch_boundary;   // REJECTION_CLOSE boundary saved at touch
   string            touch_kind;       // PRICE_INTO_ZONE / ZONE_TO_PRICE
   int               confirm_bars;
  };

//--- The single owned trade (v1: max one position per EA/symbol)
struct BBMTrade
  {
   bool              active;
   ulong             ticket;
   long              position_id;
   int               dir;
   datetime          open_time;
   double            fill;
   double            volume;
   double            requested_volume;
   double            sl;
   double            tp;
   double            planned_risk;
   double            mae;
   double            mfe;
   ulong             order_ticket;
   ulong             deal_id;
   bool              protection_ok;
   datetime          pending_since;
  };

#endif
