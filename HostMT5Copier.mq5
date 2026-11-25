//+------------------------------------------------------------------+
//| HostMT5 Copier (free): copy trades between MT5 terminals on    |
//| the same computer. Attach in MASTER mode on the account you trade |
//| and in SLAVE mode on each account that should follow.             |
//| Master and slaves meet in MT5's shared folder (Common\Files).     |
//| Needs this PC on: for 24/7 copying between brokers, use HostMT5  |
//| (hostmt5.com), where copying runs in the cloud with no EA needed. |
//+------------------------------------------------------------------+
#property copyright "HostMT5"
#property version   "1.00"
#property description "Free trade copier: master -> any number of slaves on this computer."
#property description "Lot multiplier or fixed lot, reverse, max lot, symbol suffix, SL/TP sync."
#include <Trade\Trade.mqh>

enum ENUM_ROLE { ROLE_MASTER = 0, ROLE_SLAVE = 1 };
enum ENUM_LOTS { LOTS_MULTIPLIER = 0, LOTS_FIXED = 1 };

input ENUM_ROLE InpRole        = ROLE_MASTER;      // Role
input string    InpChannel     = "main";           // Channel name (same on master and its slaves)
input ENUM_LOTS InpLotMode     = LOTS_MULTIPLIER;  // Slave: lot rule
input double    InpLotValue    = 1.0;              // Slave: multiplier, or fixed lot
input double    InpMaxLot      = 0.0;              // Slave: maximum lot (0 = no cap)
input bool      InpReverse     = false;            // Slave: reverse (buy <-> sell, SL <-> TP)
input bool      InpCopySLTP    = true;             // Slave: copy SL/TP and their changes
input bool      InpCopyExisting= false;            // Slave: also copy trades already open at start
input string    InpPrefix      = "";               // Slave: symbol prefix on this broker
input string    InpSuffix      = "";               // Slave: symbol suffix on this broker (e.g. .pro)
input int       InpSlippage    = 20;               // Slave: max slippage (points)
input long      InpMagic       = 7700770;          // Magic number of copied trades

CTrade trade;
string FileName() { return "HostMT5Copier\\" + InpChannel + ".csv"; }
ulong  g_skip[];                                    // master tickets that were open when the slave started
bool   g_seeded = false;
datetime g_lastBeat = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic); trade.SetDeviationInPoints(InpSlippage);
   EventSetMillisecondTimer(250);
   Comment("HostMT5 Copier: ", InpRole == ROLE_MASTER ? "MASTER" : "SLAVE", " on channel '", InpChannel, "'");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r) { EventKillTimer(); Comment(""); }
void OnTimer() { if (InpRole == ROLE_MASTER) WriteMaster(); else RunSlave(); }
void OnTick()  { OnTimer(); }

//--- master: snapshot of its own positions (copies made by this EA are left out, so chains never loop)
void WriteMaster()
{
   string tmp = FileName() + ".tmp";
   int h = FileOpen(tmp, FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ';');
   if (h == INVALID_HANDLE) return;
   FileWrite(h, "beat", (long)TimeLocal());
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i); if (!PositionSelectByTicket(t)) continue;
      if (PositionGetInteger(POSITION_MAGIC) == InpMagic) continue;
      FileWrite(h, (long)t, PositionGetString(POSITION_SYMBOL), (long)PositionGetInteger(POSITION_TYPE),
                DoubleToString(PositionGetDouble(POSITION_VOLUME), 2), DoubleToString(PositionGetDouble(POSITION_SL), 8), DoubleToString(PositionGetDouble(POSITION_TP), 8));
   }
   FileClose(h);
   FileMove(tmp, FILE_COMMON, FileName(), FILE_COMMON | FILE_REWRITE);   // readers never see a half-written file
}

//--- slave
struct MPos { ulong ticket; string symbol; long type; double vol; double sl; double tp; };

bool ReadMaster(MPos &out[])
{
   int h = FileOpen(FileName(), FILE_READ | FILE_CSV | FILE_COMMON | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE, ';');
   if (h == INVALID_HANDLE) return false;
   ArrayResize(out, 0); bool ok = false;
   while (!FileIsEnding(h))
   {
      string a = FileReadString(h); if (a == "") { if (FileIsLineEnding(h)) continue; else break; }
      if (a == "beat") { g_lastBeat = (datetime)StringToInteger(FileReadString(h)); ok = true; continue; }
      MPos p; p.ticket = (ulong)StringToInteger(a); p.symbol = FileReadString(h); p.type = StringToInteger(FileReadString(h));
      p.vol = StringToDouble(FileReadString(h)); p.sl = StringToDouble(FileReadString(h)); p.tp = StringToDouble(FileReadString(h));
      int n = ArraySize(out); ArrayResize(out, n + 1); out[n] = p;
   }
   FileClose(h); return ok;
}

bool Skipped(ulong t) { for (int i = 0; i < ArraySize(g_skip); i++) if (g_skip[i] == t) return true; return false; }
string Tag(ulong t) { return "mc " + (string)t; }

ulong FindCopy(ulong master)
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if (PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_COMMENT) == Tag(master)) return t;
   }
   return 0;
}

string MapSymbol(string s)
{
   string base = s; int dot = StringFind(base, "."); if (dot > 0) base = StringSubstr(base, 0, dot);
   string cand = InpPrefix + base + InpSuffix;
   if (SymbolSelect(cand, true)) return cand;
   if (SymbolSelect(s, true)) return s;
   return "";
}

double Lots(string sym, double masterVol)
{
   double v = InpLotMode == LOTS_FIXED ? InpLotValue : masterVol * InpLotValue;
   if (InpMaxLot > 0) v = MathMin(v, InpMaxLot);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP), mn = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN), mx = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if (step <= 0) step = 0.01;
   v = MathRound(v / step) * step;
   return NormalizeDouble(MathMax(mn, MathMin(mx, v)), 2);
}

void RunSlave()
{
   MPos m[];
   if (!ReadMaster(m)) { Comment("HostMT5 Copier: SLAVE on '", InpChannel, "', waiting for the master..."); return; }
   if (TimeLocal() - g_lastBeat > 10) { Comment("HostMT5 Copier: SLAVE, master silent for ", (int)(TimeLocal() - g_lastBeat), " s (is its terminal running?)"); return; }
   if (!g_seeded)
   {
      g_seeded = true;
      if (!InpCopyExisting) { ArrayResize(g_skip, ArraySize(m)); for (int i = 0; i < ArraySize(m); i++) g_skip[i] = m[i].ticket; }
   }
   // opens and SL/TP changes
   for (int i = 0; i < ArraySize(m); i++)
   {
      if (Skipped(m[i].ticket)) continue;
      bool buy = (m[i].type == POSITION_TYPE_BUY) != InpReverse;
      double sl = InpCopySLTP ? (InpReverse ? m[i].tp : m[i].sl) : 0, tp = InpCopySLTP ? (InpReverse ? m[i].sl : m[i].tp) : 0;
      ulong mine = FindCopy(m[i].ticket);
      if (mine == 0)
      {
         string sym = MapSymbol(m[i].symbol);
         if (sym == "") { Print("Copier: no symbol for ", m[i].symbol, " on this broker (set prefix/suffix)"); ArrayResize(g_skip, ArraySize(g_skip) + 1); g_skip[ArraySize(g_skip) - 1] = m[i].ticket; continue; }
         int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         bool ok = buy ? trade.Buy(Lots(sym, m[i].vol), sym, 0, NormalizeDouble(sl, dg), NormalizeDouble(tp, dg), Tag(m[i].ticket))
                       : trade.Sell(Lots(sym, m[i].vol), sym, 0, NormalizeDouble(sl, dg), NormalizeDouble(tp, dg), Tag(m[i].ticket));
         if (!ok) Print("Copier: copy of #", m[i].ticket, " failed: ", trade.ResultRetcodeDescription());
      }
      else if (InpCopySLTP && PositionSelectByTicket(mine))
      {
         int dg = (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS);
         if (MathAbs(PositionGetDouble(POSITION_SL) - sl) > SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT) / 2 ||
             MathAbs(PositionGetDouble(POSITION_TP) - tp) > SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT) / 2)
            trade.PositionModify(mine, NormalizeDouble(sl, dg), NormalizeDouble(tp, dg));
      }
   }
   // closes: my copies whose master position is gone
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if (!PositionSelectByTicket(t) || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      string c = PositionGetString(POSITION_COMMENT); if (StringFind(c, "mc ") != 0) continue;
      ulong master = (ulong)StringToInteger(StringSubstr(c, 3)); bool alive = false;
      for (int k = 0; k < ArraySize(m); k++) if (m[k].ticket == master) { alive = true; break; }
      if (!alive) trade.PositionClose(t, InpSlippage);
   }
   Comment("HostMT5 Copier: SLAVE on '", InpChannel, "', master has ", ArraySize(m), " position(s)");
}
