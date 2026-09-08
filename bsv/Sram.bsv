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

  RegFile#(Bit#(TLog#(words)), Bit#(dw)) mem <- mkRegFileFull;

  interface RegIf regs;
    method ActionValue#(RegRsp#(dw)) access(RegReq#(aw, dw) r);
      Bit#(TLog#(words)) i = truncate(r.addr >> 2);
      Bit#(dw) old = mem.sub(i);
      if (r.write) mem.upd(i, applyStrb(old, r.wdata, r.wstrb));
      return RegRsp { rdata: old, err: False };
    endmethod
  endinterface
endmodule

endpackage
