//+------------------------------------------------------------------+
//|                                     Momentum_Engulfing_VWAP.mq5  |
//|                                     Portfolio Proof of Execution |
//+------------------------------------------------------------------+
#property copyright "Execution Portfolio"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

//--- 1. Core Risk Inputs
input double InpRiskPct           = 1.0;  // Risk Per Trade (%)
input double InpATRFloorMult      = 1.0;  // Minimum SL Distance (ATR Multiplier)
input double InpATRTakeProfitMult = 0.0;  // Take Profit ATR Multiplier (0.0 = Disabled)
input double InpATRTrailMult      = 2.5;  // ATR Trailing Multiplier

//--- 2. Indicator & Metric Inputs
input int    InpSMAPeriod         = 20;   // SMA Period
input int    InpATRPeriod         = 14;   // ATR Period
input double InpMinRVOL           = 1.2;  // Minimum Relative Volume (RVOL)
input double InpMaxEngulfMult     = 4.0;  // Max Engulfing Size vs Prev Candle (Exhaustion)

//--- 3. Institutional Time & Regime Filters
input int    InpNYOpenHour        = 16;   // NY Open Hour (Broker Server Time)
input int    InpTradeStartHour    = 10;   // Start Trading Hour (Broker Time)
input int    InpTradeEndHour      = 19;   // Stop Trading Hour (Broker Time)
input int    InpFridayCloseHour   = 21;   // Liquidate all at 21:00 broker time

//--- 4. Day of Week Execution Switches (Default to True to prevent curve-fitting)
input bool   InpTradeMondays      = true;
input bool   InpTradeTuesdays     = true;
input bool   InpTradeWednesdays   = true; 
input bool   InpTradeThursdays    = true;
input bool   InpTradeFridays      = true;

//--- Global Variables
int sma_handle, atr_handle;
double sma_buffer[], atr_buffer[];
MqlRates rates[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() {
    sma_handle = iMA(_Symbol, _Period, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    atr_handle = iATR(_Symbol, _Period, InpATRPeriod);
    
    ArraySetAsSeries(sma_buffer, true);
    ArraySetAsSeries(atr_buffer, true);
    ArraySetAsSeries(rates, true);
    
    if(sma_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE) {
        Print("Failed to load indicators.");
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    IndicatorRelease(sma_handle);
    IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Tick Execution                                                   |
//+------------------------------------------------------------------+
void OnTick() {
    static datetime last_time = 0;
    datetime current_time = iTime(_Symbol, _Period, 0);
    
    // 1. Force Friday Liquidation (Tick-level check)
    MqlDateTime dt_now;
    TimeToStruct(TimeCurrent(), dt_now);
    if(dt_now.day_of_week == 5 && dt_now.hour >= InpFridayCloseHour) {
        if(PositionsTotal() > 0) CloseAllPositions();
        return; 
    }

    // 2. Strict Bar-Close Execution for new entries
    if(current_time == last_time) return;
    
    // 3. Day of Week Filter
    if(dt_now.day_of_week == 1 && !InpTradeMondays) return;
    if(dt_now.day_of_week == 2 && !InpTradeTuesdays) return;
    if(dt_now.day_of_week == 3 && !InpTradeWednesdays) return;
    if(dt_now.day_of_week == 4 && !InpTradeThursdays) return;
    if(dt_now.day_of_week == 5 && !InpTradeFridays) return;

    // 4. Intraday Time Filter
    if(dt_now.hour < InpTradeStartHour || dt_now.hour > InpTradeEndHour) return;
    
    // Memory expanded to 1500 to support lower TF VWAP calculations
    if(CopyRates(_Symbol, _Period, 0, 1500, rates) <= 0) return;
    if(CopyBuffer(sma_handle, 0, 0, 3, sma_buffer) <= 0) return;
    if(CopyBuffer(atr_handle, 0, 0, 3, atr_buffer) <= 0) return;

    last_time = current_time;

    ManageTrailingStop();

    // Prevent stacking orders
    if(PositionsTotal() > 0) return;

    // --- RVOL FILTER ---
    double sum_vol = 0;
    for(int i = 2; i <= 21; i++) sum_vol += (double)rates[i].tick_volume;
    double avg_vol = sum_vol / 20.0;
    double rvol = (avg_vol > 0) ? ((double)rates[1].tick_volume / avg_vol) : 0;
    
    if(rvol < InpMinRVOL) return; 

    double vwap = CalculateSessionVWAP();
    if(vwap == 0) return;

    // --- SHARED CANDLE METRICS ---
    double prev_range = rates[2].high - rates[2].low;
    double curr_range = rates[1].high - rates[1].low;
    bool valid_exhaustion = (prev_range > 0) ? (curr_range <= (InpMaxEngulfMult * prev_range)) : false;

    // --- BULLISH ENGULFING LOGIC ---
    bool above_sma = rates[1].close > sma_buffer[1];
    bool above_vwap = rates[1].close > vwap;
    
    bool is_prev_bear = rates[2].close < rates[2].open;
    bool is_curr_bull = rates[1].close > rates[1].open;
    bool is_engulfing_bull = (rates[1].close >= rates[2].open) && (rates[1].open <= rates[2].close);

    if(above_sma && above_vwap && is_prev_bear && is_curr_bull && is_engulfing_bull && valid_exhaustion) {
        double sl = rates[1].low; 
        ExecuteTrade(ORDER_TYPE_BUY, sl);
        return; 
    }
    
    // --- BEARISH ENGULFING LOGIC ---
    bool below_sma = rates[1].close < sma_buffer[1];
    bool below_vwap = rates[1].close < vwap;
    
    bool is_prev_bull = rates[2].close > rates[2].open;
    bool is_curr_bear = rates[1].close < rates[1].open;
    bool is_engulfing_bear = (rates[1].close <= rates[2].open) && (rates[1].open >= rates[2].close);

    if(below_sma && below_vwap && is_prev_bull && is_curr_bear && is_engulfing_bear && valid_exhaustion) {
        double sl = rates[1].high; 
        ExecuteTrade(ORDER_TYPE_SELL, sl);
    }
}

//+------------------------------------------------------------------+
//| Dynamic Position Sizing (Contract Size Math Patch)               |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double sl) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double entry_price = (type == ORDER_TYPE_BUY) ? ask : bid;
    
    double sl_distance = MathAbs(entry_price - sl);
    double point_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * point_size;
    
    // Enforce ATR-Based Minimum SL Distance
    double min_sl_dist = atr_buffer[1] * InpATRFloorMult;
    if(sl_distance < min_sl_dist) {
        sl_distance = min_sl_dist;
        sl = (type == ORDER_TYPE_BUY) ? (entry_price - sl_distance) : (entry_price + sl_distance);
    }

    double tp = 0;
    if(InpATRTakeProfitMult > 0) {
        double tp_dist = atr_buffer[1] * InpATRTakeProfitMult;
        tp = (type == ORDER_TYPE_BUY) ? (entry_price + tp_dist) : (entry_price - tp_dist);
    }

    // Spread Penalty
    double effective_sl_distance = sl_distance + (spread * 2.0); 

    // --- HARD MATH CORRECTION: CONTRACT SIZING ---
    double risk_amount = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * (InpRiskPct / 100.0);
    double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE); 
    
    double loss_per_lot = effective_sl_distance * contract_size; 
    if(loss_per_lot <= 0) return;
    
    double volume = risk_amount / loss_per_lot;
    
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    volume = MathFloor(volume / step_lot) * step_lot;
    
    // Hard mechanical limit: Do not trade if minimum lot violates risk profile
    if(volume < min_lot) return; 
    if(volume > max_lot) volume = max_lot;

    if(type == ORDER_TYPE_BUY) trade.Buy(volume, _Symbol, ask, sl, tp, "Engulf_Portfolio");
    else trade.Sell(volume, _Symbol, bid, sl, tp, "Engulf_Portfolio");
}

//+------------------------------------------------------------------+
//| Session VWAP Calculation                                         |
//+------------------------------------------------------------------+
double CalculateSessionVWAP() {
    int start_index = -1;
    for(int i = 1; i < 1499; i++) {
        MqlDateTime time_struct;
        TimeToStruct(rates[i].time, time_struct);
        if(time_struct.hour == InpNYOpenHour) {
            start_index = i;
            MqlDateTime older_struct;
            TimeToStruct(rates[i+1].time, older_struct);
            if(older_struct.hour != InpNYOpenHour) break;
        }
    }
    
    if(start_index == -1) return 0;

    double sum_pv = 0;
    double sum_vol = 0;
    
    for(int i = start_index; i >= 1; i--) {
        double typical_price = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
        double vol = (double)rates[i].tick_volume;
        sum_pv += typical_price * vol;
        sum_vol += vol;
    }
    
    return (sum_vol > 0) ? (sum_pv / sum_vol) : 0;
}

//+------------------------------------------------------------------+
//| Ratchet Trailing Stop Logic                                      |
//+------------------------------------------------------------------+
void ManageTrailingStop() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            double current_sl = PositionGetDouble(POSITION_SL);
            double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
            double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            long type = PositionGetInteger(POSITION_TYPE);
            
            double trail_distance = atr_buffer[1] * InpATRTrailMult;

            if(type == POSITION_TYPE_BUY) {
                double new_sl = current_price - trail_distance;
                if(new_sl > entry_price && (new_sl > current_sl || current_sl == 0)) {
                    trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
                }
            }
            else if(type == POSITION_TYPE_SELL) {
                double new_sl = current_price + trail_distance;
                if(new_sl < entry_price && (new_sl < current_sl || current_sl == 0)) {
                    trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Liquidate All Positions (Panic Button / Friday Close)            |
//+------------------------------------------------------------------+
void CloseAllPositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            trade.PositionClose(ticket);
        }
    }
}