//+------------------------------------------------------------------+
//| EMA_RegimeTouch.mq5                                              |
//| Copyright 2025, BotHub Trading                                   |
//|                                                                  |
//| Strategy: EMA8/EMA15 Regime Touch                                |
//|   - Regime detection via EMA8 vs EMA15 crossover                 |
//|   - Entry triggered when price touches either EMA in the active  |
//|     regime direction                                             |
//|   - Optional regime-flip exit closes opposite trades immediately |
//+------------------------------------------------------------------+
#property copyright "BotHub Trading"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Indicator inputs
input int                EMA_Fast_Period   = 8;           // EMA fast period
input int                EMA_Slow_Period   = 15;          // EMA slow period
input ENUM_APPLIED_PRICE EMA_Price         = PRICE_CLOSE; // EMA applied price

//--- Trade inputs
input double LotSize           = 0.01;   // Lot size
input double StopLoss_Pips     = 50.0;   // Stop loss (pips)
input double TakeProfit_Pips   = 100.0;  // Take profit (pips)
input int    MaxOpenTrades     = 1;      // Max concurrent trades (by magic)
input bool   CloseOnRegimeFlip = true;   // Close trades on regime flip

//--- Filter inputs
input bool   UseCandleConfirm  = true;   // Require candle close confirmation
input double TouchTolerance    = 0.0;    // Extra tolerance in points added to EMA for touch check
input double MaxSpread_Pips    = 3.0;    // Max allowed spread in pips (0 = disabled)

//--- General inputs
input int    MagicNumber  = 202501;              // Magic number
input int    Slippage     = 10;                  // Max slippage in points
input string TradeComment = "EMA_RegimeTouch";   // Order comment
input bool   EnableBuy    = true;                // Enable buy trades
input bool   EnableSell   = true;                // Enable sell trades

//--- Regime enumeration
enum ENUM_REGIME { REGIME_NONE = 0, REGIME_BULL = 1, REGIME_BEAR = -1 };

//--- Global state
int            g_emaFastHandle = INVALID_HANDLE;
int            g_emaSlowHandle = INVALID_HANDLE;
ENUM_REGIME    g_regime        = REGIME_NONE;   // Active market regime

CTrade g_trade; // MQL5 trade helper

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Validate periods
    if (EMA_Fast_Period <= 0 || EMA_Slow_Period <= 0)
    {
        Print("ERROR: EMA periods must be > 0");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (EMA_Fast_Period >= EMA_Slow_Period)
    {
        Print("ERROR: EMA_Fast_Period must be less than EMA_Slow_Period");
        return INIT_PARAMETERS_INCORRECT;
    }

    //--- Create EMA indicator handles
    g_emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast_Period, 0, MODE_EMA, EMA_Price);
    if (g_emaFastHandle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create EMA fast handle");
        return INIT_FAILED;
    }

    g_emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow_Period, 0, MODE_EMA, EMA_Price);
    if (g_emaSlowHandle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create EMA slow handle");
        return INIT_FAILED;
    }

    //--- Configure CTrade
    g_trade.SetExpertMagicNumber(MagicNumber);
    g_trade.SetDeviationInPoints(Slippage);
    g_trade.SetTypeFilling(ORDER_FILLING_FOK);

    Print("EMA_RegimeTouch initialized | Symbol=", _Symbol,
          " | EMA Fast=", EMA_Fast_Period,
          " | EMA Slow=", EMA_Slow_Period,
          " | Magic=", MagicNumber);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if (g_emaFastHandle != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
    if (g_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
    Print("EMA_RegimeTouch deinitialized | Reason=", reason);
}

//+------------------------------------------------------------------+
//| Main tick handler                                                |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- New-bar guard: strategy logic runs once per completed candle
    static datetime s_lastBar    = 0;
    static datetime s_lastTrade  = 0; // candle on which last trade was opened

    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    if (currentBar == s_lastBar) return;
    s_lastBar = currentBar;

    //--- Read EMA values for current (index 1 = last closed bar) and previous (index 2)
    //    Index 0 is the still-forming bar; we read from the most recent CLOSED bar.
    double emaFast[3], emaSlow[3];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);

    if (CopyBuffer(g_emaFastHandle, 0, 0, 3, emaFast) < 3)
    {
        Print("WARNING: Not enough EMA fast data");
        return;
    }
    if (CopyBuffer(g_emaSlowHandle, 0, 0, 3, emaSlow) < 3)
    {
        Print("WARNING: Not enough EMA slow data");
        return;
    }

    //--- Index mapping (ArraySetAsSeries=true): [0]=current forming, [1]=prev closed, [2]=2 bars ago
    double emaFastCurr = emaFast[1];  // EMA8 on last closed bar
    double emaSlowCurr = emaSlow[1];  // EMA15 on last closed bar
    double emaFastPrev = emaFast[2];  // EMA8 on bar before that
    double emaSlowPrev = emaSlow[2];  // EMA15 on bar before that

    //--- Read OHLC of the last closed bar (index 1)
    double barOpen  = iOpen (_Symbol, PERIOD_CURRENT, 1);
    double barHigh  = iHigh (_Symbol, PERIOD_CURRENT, 1);
    double barLow   = iLow  (_Symbol, PERIOD_CURRENT, 1);
    double barClose = iClose(_Symbol, PERIOD_CURRENT, 1);

    //--- Step 1: Detect crossover and update regime
    ENUM_REGIME prevRegime = g_regime;
    bool bullCross = (emaFastPrev <= emaSlowPrev) && (emaFastCurr > emaSlowCurr);
    bool bearCross = (emaFastPrev >= emaSlowPrev) && (emaFastCurr < emaSlowCurr);

    if (bullCross)
    {
        g_regime = REGIME_BULL;
        Print("Regime change → BULLISH | EMA8=", emaFastCurr, " EMA15=", emaSlowCurr);
    }
    else if (bearCross)
    {
        g_regime = REGIME_BEAR;
        Print("Regime change → BEARISH | EMA8=", emaFastCurr, " EMA15=", emaSlowCurr);
    }

    //--- Step 2: Close opposite trades on regime flip (if enabled)
    if (CloseOnRegimeFlip && g_regime != REGIME_NONE && g_regime != prevRegime)
    {
        if (g_regime == REGIME_BULL)
        {
            CloseAllByType(POSITION_TYPE_SELL);
        }
        else if (g_regime == REGIME_BEAR)
        {
            CloseAllByType(POSITION_TYPE_BUY);
        }
    }

    //--- Step 3: No valid regime → nothing to trade
    if (g_regime == REGIME_NONE) return;

    //--- Step 4: One-trade-per-candle guard
    if (currentBar == s_lastTrade) return;

    //--- Step 5: Max-open-trades guard (count only EA's own trades by magic)
    if (CountOpenByMagic() >= MaxOpenTrades) return;

    //--- Step 6: Spread check
    if (MaxSpread_Pips > 0.0)
    {
        double spreadPips = GetSpreadPips();
        if (spreadPips > MaxSpread_Pips)
        {
            Print("Spread too wide: ", spreadPips, " pips (max=", MaxSpread_Pips, ")");
            return;
        }
    }

    //--- Step 7: Calculate touch tolerance in price units
    double tolPrice = TouchTolerance * _Point;

    //--- Step 8: Evaluate entry conditions
    bool tradeOpened = false;

    if (g_regime == REGIME_BULL && EnableBuy)
    {
        //--- Touch check: candle low touched EMA8 or EMA15
        bool touchEMA8  = (barLow <= emaFastCurr + tolPrice);
        bool touchEMA15 = (barLow <= emaSlowCurr + tolPrice);

        //--- Candle confirmation: closed bullish
        bool candleConfirm = UseCandleConfirm ? (barClose > barOpen) : true;

        //--- No opposing trades open
        bool noSell = (CountOpenByType(POSITION_TYPE_SELL) == 0);

        if ((touchEMA8 || touchEMA15) && candleConfirm && noSell)
        {
            if (OpenBuy())
            {
                s_lastTrade  = currentBar;
                tradeOpened  = true;
            }
        }
    }

    if (!tradeOpened && g_regime == REGIME_BEAR && EnableSell)
    {
        //--- Touch check: candle high touched EMA8 or EMA15
        bool touchEMA8  = (barHigh >= emaFastCurr - tolPrice);
        bool touchEMA15 = (barHigh >= emaSlowCurr - tolPrice);

        //--- Candle confirmation: closed bearish
        bool candleConfirm = UseCandleConfirm ? (barClose < barOpen) : true;

        //--- No opposing trades open
        bool noBuy = (CountOpenByType(POSITION_TYPE_BUY) == 0);

        if ((touchEMA8 || touchEMA15) && candleConfirm && noBuy)
        {
            if (OpenSell())
            {
                s_lastTrade = currentBar;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open a BUY market order                                         |
//+------------------------------------------------------------------+
bool OpenBuy()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if (ask <= 0)
    {
        Print("ERROR: Invalid ASK price");
        return false;
    }

    double pipUnit = PipToPrice();
    double sl = NormalizeDouble(ask - StopLoss_Pips   * pipUnit, _Digits);
    double tp = NormalizeDouble(ask + TakeProfit_Pips * pipUnit, _Digits);

    bool result = g_trade.Buy(LotSize, _Symbol, ask, sl, tp, TradeComment);
    if (!result || g_trade.ResultRetcode() != TRADE_RETCODE_DONE)
    {
        Print("BUY OrderSend failed | retcode=", g_trade.ResultRetcode(),
              " | comment=", g_trade.ResultComment());
        return false;
    }

    Print("BUY opened | Ticket=", g_trade.ResultOrder(),
          " | Price=", ask,
          " | SL=", sl,
          " | TP=", tp,
          " | Lots=", LotSize);
    return true;
}

//+------------------------------------------------------------------+
//| Open a SELL market order                                        |
//+------------------------------------------------------------------+
bool OpenSell()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (bid <= 0)
    {
        Print("ERROR: Invalid BID price");
        return false;
    }

    double pipUnit = PipToPrice();
    double sl = NormalizeDouble(bid + StopLoss_Pips   * pipUnit, _Digits);
    double tp = NormalizeDouble(bid - TakeProfit_Pips * pipUnit, _Digits);

    bool result = g_trade.Sell(LotSize, _Symbol, bid, sl, tp, TradeComment);
    if (!result || g_trade.ResultRetcode() != TRADE_RETCODE_DONE)
    {
        Print("SELL OrderSend failed | retcode=", g_trade.ResultRetcode(),
              " | comment=", g_trade.ResultComment());
        return false;
    }

    Print("SELL opened | Ticket=", g_trade.ResultOrder(),
          " | Price=", bid,
          " | SL=", sl,
          " | TP=", tp,
          " | Lots=", LotSize);
    return true;
}

//+------------------------------------------------------------------+
//| Close all open positions of a given type belonging to this EA   |
//+------------------------------------------------------------------+
void CloseAllByType(ENUM_POSITION_TYPE posType)
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;
        if (PositionGetString(POSITION_SYMBOL)   != _Symbol)     continue;
        if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;

        bool closed = g_trade.PositionClose(ticket, Slippage);
        if (!closed || g_trade.ResultRetcode() != TRADE_RETCODE_DONE)
        {
            Print("Failed to close position | Ticket=", ticket,
                  " | retcode=", g_trade.ResultRetcode(),
                  " | comment=", g_trade.ResultComment());
        }
        else
        {
            Print("Position closed on regime flip | Ticket=", ticket,
                  " | Type=", EnumToString(posType));
        }
    }
}

//+------------------------------------------------------------------+
//| Count open positions for this EA (by magic number and symbol)   |
//+------------------------------------------------------------------+
int CountOpenByMagic()
{
    int count = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;
        if (PositionGetString(POSITION_SYMBOL)       != _Symbol)     continue;
        if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Count open positions of specific type for this EA               |
//+------------------------------------------------------------------+
int CountOpenByType(ENUM_POSITION_TYPE posType)
{
    int count = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;
        if (PositionGetString(POSITION_SYMBOL)       != _Symbol)     continue;
        if ((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;
        count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Return current spread in pips (broker-agnostic)                 |
//+------------------------------------------------------------------+
double GetSpreadPips()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    // For 5-digit brokers (EURUSD = 1.23456, _Digits=5) spread in points / 10 = pips
    // For 4-digit brokers (_Digits=4) spread in points = pips
    double spreadPoints = (ask - bid) / _Point;
    return spreadPoints / ((_Digits == 5 || _Digits == 3) ? 10.0 : 1.0);
}

//+------------------------------------------------------------------+
//| Convert pips to a price distance, handling 3/5-digit brokers    |
//+------------------------------------------------------------------+
double PipToPrice()
{
    // On a 5-digit broker: 1 pip = 10 points = 10 * _Point
    // On a 4-digit broker: 1 pip =  1 point  =  1 * _Point
    double multiplier = ((_Digits == 5 || _Digits == 3) ? 10.0 : 1.0);
    return multiplier * _Point;
}
//+------------------------------------------------------------------+
