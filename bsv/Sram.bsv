package Sram;

import RegFile::*;
import RegIf::*;

// 恒定的只读桩：特性关掉时占位，写进去什么也不发生，综合器整片消掉
function Reg#(t) roReg(t v) =
  interface Reg;
    method t _read = v;
    method Action _write(t x) = noAction;
  endinterface;

function Wire#(t) roWire(t v) =
  interface Wire;
    method t _read = v;
    method Action _write(t x) = noAction;
  endinterface;

// 片上存储。本版用寄存器阵列——ICS55 的 SRAM 宏不在开放 PDK 里，拿不到就
// 不能假装有（`notes/ecos-*` 已经记过这件事）。所以这个 IP 现在只适合放
// 几 KB 的引导码与栈；真正的容量等宏到手再换实现，接口不必动。
//
// D38 那条「超过约 900 位就上 SRAM 宏」在这里成立：这是按地址读一项的存储，
// 不是并行比对，跟 TLB、cache 标签、MAC 学习表不是一回事。

// `sync` 开着就是宏的形状：地址进去，**下一拍**数据才出来。
// 这一位不是性能选项，是「能不能换成宏」的开关。
typedef struct {
  Bool sync;
} SramCfg;

// 两个口都在接口上，不随配置变形（与 uart 的 cts/rts 同一条规矩）：
// 没被接的那个退化成常量，综合器整片消掉，不额外花钱。
interface SramIfc#(numeric type aw, numeric type dw, numeric type words);
  interface RegIf#(aw, dw)     regs;   // 同拍答，sync 关时用
  interface RegTarget#(aw, dw) slow;   // 下一拍答，sync 开时用
endinterface

module mkSram#(SramCfg cfg)(SramIfc#(aw, dw, words))
    provisos (Mul#(TDiv#(dw, 8), 8, dw), Add#(_a, TLog#(words), aw),
              Bits#(Bit#(dw), dw));

  // 按说的字数分配，不按下一个 2 的幂。mkRegFileFull 走的是索引类型的
  // 全量程：192 字的索引要 8 位，于是它真给 256 字，面积与 256 字一模一样
  // （实测两者都是 94,372.60）。价目表在两点之间线性插值，于是低估三成，
  // 「恒为高估」的承诺当场作废——这是证伪点量出来的。
  RegFile#(Bit#(TLog#(words)), Bit#(dw)) mem <-
    mkRegFile(0, fromInteger(valueOf(words) - 1));

  // 同步那一路的状态。只有 syncStep 一条规则写，方法只发线——
  // `ready` 与 `rspValid` 会被发起方在同一条规则里读，状态若被方法直接写，
  // 两者会对调用者提出相反的次序要求，那条规则就永不触发。
  // 按需例化：关掉时退化成常量，综合器整片消掉。只挡逻辑不挡例化的开关
  // 一分钱都不省（uart 那边已经写过这条）。
  Reg#(Bool)             sBusy = roReg(False);
  Reg#(Bool)             sAns  = roReg(False);
  Reg#(Bit#(dw))         sData = roReg(0);
  Reg#(Bool)             sErr  = roReg(False);
  Reg#(RegReq#(aw, dw))  sQ    = roReg(unpack(0));
  Wire#(Bool)            sTake = roWire(False);
  Wire#(RegReq#(aw, dw)) sR    = roWire(unpack(0));
  if (cfg.sync) begin
    sBusy <- mkReg(False);
    sAns  <- mkReg(False);
    sData <- mkReg(0);
    sErr  <- mkReg(False);
    sQ    <- mkRegU;
    sTake <- mkDWire(False);
    sR    <- mkDWire(unpack(0));
  end

  rule syncStep (cfg.sync);
    if (sBusy) begin
      Bit#(TLog#(words)) i = truncate(sQ.addr >> 2);
      Bool oob = i > fromInteger(valueOf(words) - 1);
      Bit#(dw) old = oob ? 0 : mem.sub(i);
      if (sQ.write && !oob) mem.upd(i, applyStrb(old, sQ.wdata, sQ.wstrb));
      sData <= old;
      sErr  <= oob;
      sAns  <= True;
      sBusy <= False;
    end else begin
      sAns <= False;
      if (sTake) begin sQ <= sR; sBusy <= True; end
    end
  endrule

  interface RegIf regs;
    method ActionValue#(RegRsp#(dw)) access(RegReq#(aw, dw) r);
      Bit#(TLog#(words)) i = truncate(r.addr >> 2);
      // 索引位宽是 2 的幂，字数不一定是——超出的地址要报错，不能悄悄绕回来
      Bool oob = i > fromInteger(valueOf(words) - 1);
      Bit#(dw) old = oob ? 0 : mem.sub(i);
      // sync 开着时这一路不该有人用：报错，不悄悄给个值
      if (r.write && !oob && !cfg.sync) mem.upd(i, applyStrb(old, r.wdata, r.wstrb));
      return RegRsp { rdata: cfg.sync ? 0 : old, err: oob || cfg.sync };
    endmethod
  endinterface

  interface RegTarget slow;
    method Action req(Bool valid, RegReq#(aw, dw) r);
      if (cfg.sync && valid && !sBusy && !sAns) begin
        sTake <= True;
        sR    <= r;
      end
    endmethod
    method Bool ready = cfg.sync && !sBusy && !sAns;
    method Bool rspValid = sAns;
    method RegRsp#(dw) rsp = RegRsp { rdata: sData, err: sErr };
  endinterface
endmodule

endpackage
