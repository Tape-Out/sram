package Sram;

import RegFile::*;
import RegIf::*;

// 片上存储。本版用寄存器阵列——ICS55 的 SRAM 宏不在开放 PDK 里，拿不到就
// 不能假装有（`notes/ecos-*` 已经记过这件事）。所以这个 IP 现在只适合放
// 几 KB 的引导码与栈；真正的容量等宏到手再换实现，接口不必动。
//
// D38 那条「超过约 900 位就上 SRAM 宏」在这里成立：这是按地址读一项的存储，
// 不是并行比对，跟 TLB、cache 标签、MAC 学习表不是一回事。

typedef struct {
  Bit#(0) none;
} SramCfg;

interface SramIfc#(numeric type aw, numeric type dw, numeric type words);
  interface RegIf#(aw, dw) regs;
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

  interface RegIf regs;
    method ActionValue#(RegRsp#(dw)) access(RegReq#(aw, dw) r);
      Bit#(TLog#(words)) i = truncate(r.addr >> 2);
      // 索引位宽是 2 的幂，字数不一定是——超出的地址要报错，不能悄悄绕回来
      Bool oob = i > fromInteger(valueOf(words) - 1);
      Bit#(dw) old = oob ? 0 : mem.sub(i);
      if (r.write && !oob) mem.upd(i, applyStrb(old, r.wdata, r.wstrb));
      return RegRsp { rdata: old, err: oob };
    endmethod
  endinterface
endmodule

endpackage
