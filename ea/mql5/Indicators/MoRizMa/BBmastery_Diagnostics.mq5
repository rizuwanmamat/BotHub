//+------------------------------------------------------------------+
//| BBmastery_Diagnostics.mq5                                        |
//| Visual validation overlay for MoRizMa BBmastery (spec 18)        |
//|                                                                  |
//| Attach to the SETUP timeframe chart. Plots BB20, LWMA5/10 High & |
//| Low, EMA50, and immutable markers on COMPLETED bars only:        |
//|   CT events (arrows), CC events (dots), TRZ warnings (circles).  |
//| ContextDir (Data Window) = last context bar completed by each    |
//| chart bar's close: +1 bull, -1 bear, 0 neutral.                  |
//| DRAFT — not compiled. Verify buffer mapping against MT5 native   |
//| Bollinger Bands / Moving Average before relying on it.           |
//+------------------------------------------------------------------+
#property copyright "MoRizMa / BotHub Trading"
#property version   "0.10"
#property indicator_chart_window
#property indicator_buffers 15
#property indicator_plots   15

#include <MoRizMa/BBmastery/Defines.mqh>

input int                   InpBBPeriod     = 20;
input double                InpBBDeviation  = 2.0;
input int                   InpMAFast       = 5;
input int                   InpMASlow       = 10;
input int                   InpEMAPeriod    = 50;
input ENUM_BBM_EVENT_MODE   InpEventMode    = BBM_EVENT_FIRST_TRANSITION;
input bool                  InpColourFilter = false;
input ENUM_TIMEFRAMES       InpContextTF    = PERIOD_H4;
input ENUM_BBM_CONTEXT_MODE InpContextMode  = BBM_CONTEXT_MIDDLE_AND_EMA50;
input int                   InpContextBars  = 2000;   // Bars to evaluate context for (cost control)
input bool                  InpShowCC       = true;
input bool                  InpShowTRZ      = true;

double BufU[], BufM[], BufD[], BufH5[], BufH10[], BufL5[], BufL10[], BufE50[];
double BufBullCT[], BufBearCT[], BufBullCC[], BufBearCC[], BufBuyW[], BufSellW[];
double BufCtx[];

int hBB = INVALID_HANDLE, hH5 = INVALID_HANDLE, hH10 = INVALID_HANDLE;
int hL5 = INVALID_HANDLE, hL10 = INVALID_HANDLE, hE50 = INVALID_HANDLE;
int hCtxBB = INVALID_HANDLE, hCtxE50 = INVALID_HANDLE;

//+------------------------------------------------------------------+
void SetupLine(const int idx, double &buf[], const string label, const color clr,
               const ENUM_LINE_STYLE style, const int width)
  {
   SetIndexBuffer(idx, buf, INDICATOR_DATA);
   PlotIndexSetInteger(idx, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(idx, PLOT_LINE_COLOR, clr);
   PlotIndexSetInteger(idx, PLOT_LINE_STYLE, style);
   PlotIndexSetInteger(idx, PLOT_LINE_WIDTH, width);
   PlotIndexSetString(idx, PLOT_LABEL, label);
   PlotIndexSetDouble(idx, PLOT_EMPTY_VALUE, EMPTY_VALUE);
  }

void SetupArrow(const int idx, double &buf[], const string label, const color clr,
                const int code, const int width)
  {
   SetIndexBuffer(idx, buf, INDICATOR_DATA);
   PlotIndexSetInteger(idx, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(idx, PLOT_ARROW, code);
   PlotIndexSetInteger(idx, PLOT_LINE_COLOR, clr);
   PlotIndexSetInteger(idx, PLOT_LINE_WIDTH, width);
   PlotIndexSetString(idx, PLOT_LABEL, label);
   PlotIndexSetDouble(idx, PLOT_EMPTY_VALUE, EMPTY_VALUE);
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   SetupLine(0, BufU,   "BB Upper",    clrSilver,      STYLE_SOLID, 1);
   SetupLine(1, BufM,   "BB Middle",   clrGray,        STYLE_DOT,   1);
   SetupLine(2, BufD,   "BB Lower",    clrSilver,      STYLE_SOLID, 1);
   SetupLine(3, BufH5,  "LWMA5 High",  clrDodgerBlue,  STYLE_SOLID, 1);
   SetupLine(4, BufH10, "LWMA10 High", clrRoyalBlue,   STYLE_SOLID, 1);
   SetupLine(5, BufL5,  "LWMA5 Low",   clrOrange,      STYLE_SOLID, 1);
   SetupLine(6, BufL10, "LWMA10 Low",  clrDarkOrange,  STYLE_SOLID, 1);
   SetupLine(7, BufE50, "EMA50",       clrBlack,       STYLE_SOLID, 2);

   SetupArrow(8,  BufBullCT, "Bull CT",     clrLimeGreen, 233, 2);
   SetupArrow(9,  BufBearCT, "Bear CT",     clrRed,       234, 2);
   SetupArrow(10, BufBullCC, "Bull CC",     clrGreen,     159, 1);
   SetupArrow(11, BufBearCC, "Bear CC",     clrMaroon,    159, 1);
   SetupArrow(12, BufBuyW,   "TRZ BuyWarn", clrMagenta,   108, 1);
   SetupArrow(13, BufSellW,  "TRZ SellWarn",clrMagenta,   108, 1);

   SetIndexBuffer(14, BufCtx, INDICATOR_DATA);
   PlotIndexSetInteger(14, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetString(14, PLOT_LABEL, "ContextDir");
   PlotIndexSetDouble(14, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   hBB  = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hH5  = iMA(_Symbol, _Period, InpMAFast, 0, MODE_LWMA, PRICE_HIGH);
   hH10 = iMA(_Symbol, _Period, InpMASlow, 0, MODE_LWMA, PRICE_HIGH);
   hL5  = iMA(_Symbol, _Period, InpMAFast, 0, MODE_LWMA, PRICE_LOW);
   hL10 = iMA(_Symbol, _Period, InpMASlow, 0, MODE_LWMA, PRICE_LOW);
   hE50 = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hCtxBB  = iBands(_Symbol, InpContextTF, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hCtxE50 = iMA(_Symbol, InpContextTF, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(hBB == INVALID_HANDLE || hH5 == INVALID_HANDLE || hH10 == INVALID_HANDLE ||
      hL5 == INVALID_HANDLE || hL10 == INVALID_HANDLE || hE50 == INVALID_HANDLE ||
      hCtxBB == INVALID_HANDLE || hCtxE50 == INVALID_HANDLE)
     {
      Print("BBM diag: handle creation failed, error ", GetLastError());
      return INIT_FAILED;
     }
   IndicatorSetString(INDICATOR_SHORTNAME, "BBmastery Diagnostics");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   int h[8];
   h[0] = hBB; h[1] = hH5; h[2] = hH10; h[3] = hL5;
   h[4] = hL10; h[5] = hE50; h[6] = hCtxBB; h[7] = hCtxE50;
   for(int i = 0; i < 8; i++)
      if(h[i] != INVALID_HANDLE)
         IndicatorRelease(h[i]);
  }

//+------------------------------------------------------------------+
bool IsBull(const int i, const double &open[], const double &close[])
  {
   if(!(close[i] > MathMax(MathMax(BufH5[i], BufH10[i]), BufM[i])))
      return false;
   return (!InpColourFilter || close[i] > open[i]);
  }

bool IsBear(const int i, const double &open[], const double &close[])
  {
   if(!(close[i] < MathMin(MathMin(BufL5[i], BufL10[i]), BufM[i])))
      return false;
   return (!InpColourFilter || close[i] < open[i]);
  }

bool IsEvent(const bool now, const bool prev)
  {
   if(!now)
      return false;
   return (InpEventMode == BBM_EVENT_EVERY_QUALIFYING_BAR) ? true : !prev;
  }

//--- Context from the last context bar CLOSED at or before closeTime (no look-ahead)
double ContextAt(const datetime closeTime)
  {
   int s = iBarShift(_Symbol, InpContextTF, closeTime, false);
   if(s < 0)
      return EMPTY_VALUE;
   if(iTime(_Symbol, InpContextTF, s) + PeriodSeconds(InpContextTF) > closeTime)
      s++;
   double c = iClose(_Symbol, InpContextTF, s);
   double m[], e[];
   if(c <= 0.0 || CopyBuffer(hCtxBB, 0, s, 1, m) != 1 || CopyBuffer(hCtxE50, 0, s, 1, e) != 1)
      return EMPTY_VALUE;
   if(InpContextMode == BBM_CONTEXT_MIDDLE_BAND_ONLY)
      return (c > m[0]) ? 1.0 : (c < m[0]) ? -1.0 : 0.0;
   if(c > m[0] && c > e[0]) return 1.0;
   if(c < m[0] && c < e[0]) return -1.0;
   return 0.0;
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   int warm = MathMax(InpBBPeriod, MathMax(InpMASlow, InpEMAPeriod)) + 2;
   if(rates_total <= warm)
      return 0;

   if(BarsCalculated(hBB) < rates_total || BarsCalculated(hH5) < rates_total ||
      BarsCalculated(hH10) < rates_total || BarsCalculated(hL5) < rates_total ||
      BarsCalculated(hL10) < rates_total || BarsCalculated(hE50) < rates_total)
      return 0;

   int toCopy = (prev_calculated <= 0 || prev_calculated > rates_total)
                ? rates_total : rates_total - prev_calculated + 1;

   if(CopyBuffer(hBB, 1, 0, toCopy, BufU)   <= 0) return 0;   // UPPER_BAND
   if(CopyBuffer(hBB, 0, 0, toCopy, BufM)   <= 0) return 0;   // BASE_LINE
   if(CopyBuffer(hBB, 2, 0, toCopy, BufD)   <= 0) return 0;   // LOWER_BAND
   if(CopyBuffer(hH5,  0, 0, toCopy, BufH5)  <= 0) return 0;
   if(CopyBuffer(hH10, 0, 0, toCopy, BufH10) <= 0) return 0;
   if(CopyBuffer(hL5,  0, 0, toCopy, BufL5)  <= 0) return 0;
   if(CopyBuffer(hL10, 0, 0, toCopy, BufL10) <= 0) return 0;
   if(CopyBuffer(hE50, 0, 0, toCopy, BufE50) <= 0) return 0;

   if(prev_calculated <= 0)
     {
      ArrayInitialize(BufBullCT, EMPTY_VALUE);
      ArrayInitialize(BufBearCT, EMPTY_VALUE);
      ArrayInitialize(BufBullCC, EMPTY_VALUE);
      ArrayInitialize(BufBearCC, EMPTY_VALUE);
      ArrayInitialize(BufBuyW,   EMPTY_VALUE);
      ArrayInitialize(BufSellW,  EMPTY_VALUE);
      ArrayInitialize(BufCtx,    EMPTY_VALUE);
     }

   int  start  = (prev_calculated <= 0) ? warm : MathMax(warm, prev_calculated - 2);
   int  period = PeriodSeconds(_Period);
   bool ctxReady = (BarsCalculated(hCtxBB) > 0 && BarsCalculated(hCtxE50) > 0);

   for(int i = start; i < rates_total; i++)
     {
      BufBullCT[i] = EMPTY_VALUE; BufBearCT[i] = EMPTY_VALUE;
      BufBullCC[i] = EMPTY_VALUE; BufBearCC[i] = EMPTY_VALUE;
      BufBuyW[i]   = EMPTY_VALUE; BufSellW[i]  = EMPTY_VALUE;
      BufCtx[i]    = EMPTY_VALUE;

      if(i == rates_total - 1)
         continue;   // forming bar: no markers until it closes

      double off = (high[i] - low[i]) * 0.3;

      if(IsEvent(IsBull(i, open, close), IsBull(i - 1, open, close)))
         BufBullCT[i] = low[i] - off;
      if(IsEvent(IsBear(i, open, close), IsBear(i - 1, open, close)))
         BufBearCT[i] = high[i] + off;

      if(InpShowCC)
        {
         bool bullCC = close[i] > BufU[i], bullCCp = close[i - 1] > BufU[i - 1];
         bool bearCC = close[i] < BufD[i], bearCCp = close[i - 1] < BufD[i - 1];
         if(bullCC && !bullCCp) BufBullCC[i] = high[i] + off * 2.0;
         if(bearCC && !bearCCp) BufBearCC[i] = low[i] - off * 2.0;
        }

      if(InpShowTRZ)
        {
         bool sellW  = MathMax(BufH5[i], BufH10[i]) >= BufU[i];
         bool sellWp = MathMax(BufH5[i - 1], BufH10[i - 1]) >= BufU[i - 1];
         bool buyW   = MathMin(BufL5[i], BufL10[i]) <= BufD[i];
         bool buyWp  = MathMin(BufL5[i - 1], BufL10[i - 1]) <= BufD[i - 1];
         if(sellW && !sellWp) BufSellW[i] = BufU[i];
         if(buyW && !buyWp)   BufBuyW[i]  = BufD[i];
        }

      if(ctxReady && i >= rates_total - InpContextBars)
         BufCtx[i] = ContextAt(time[i] + period);
     }
   return rates_total;
  }
//+------------------------------------------------------------------+
