"""sram 的行为测试台：写得进、读得回、字节选通只动被选中的那个字节、最高一字也在。

数据挑 0xA5 0x5A 这种不对称的：全零全一或者对称图案，地址算错一位、字节序
反了都看不出来。最高一字单独试一遍，因为索引是截位来的，边界最容易漏。

认矩阵：`words` 从这一点的旋钮来。
"""
import json
import pathlib
import sys

out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
out.mkdir(parents=True, exist_ok=True)
cfg = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
label = cfg.get("label", "")
words = int(cfg.get("knobs", {}).get("words", 1024))

TOP = words - 1
V0 = 0xA5A50001
V1 = 0x5A5A0002
VT = 0xDEADBEEF

txt = f'''package Sram{label}Tb;

import RegIf::*;
import Sram::*;

// 由 tb/mksramtb.py 生成，勿手改。这一点：words={words}

typedef enum {{ Write, Read, Strb, StrbCheck, Done }}
  Phase deriving (Bits, Eq);

(* synthesize *)
module mkSram{label}Tb(Empty);
  SramIfc#(16, 32, {words}) d <- mkSram(SramCfg {{ none: ? }});

  Reg#(Phase)    ph  <- mkReg(Write);
  Reg#(Bit#(8))  s   <- mkReg(0);
  Reg#(Bit#(32)) cyc <- mkReg(0);
  Reg#(Bool)     bad <- mkReg(False);

  rule tick_;
    cyc <= cyc + 1;
    if (cyc > 20000) begin
      $display("TIMEOUT in phase %0d", pack(ph));
      $finish(1);
    end
  endrule

  function Action wr(Bit#(16) a, Bit#(32) v, Bit#(4) st) = action
    let _ <- d.regs.access(RegReq {{ addr: a, write: True,
                                     wdata: v, wstrb: st }});
  endaction;

  rule write_ (ph == Write);
    case (s)
      0: wr(16'h0000, 32'h{V0:08X}, 4'hF);
      1: wr(16'h0004, 32'h{V1:08X}, 4'hF);
      2: wr(16'h{TOP * 4 & 0xFFFF:04X}, 32'h{VT:08X}, 4'hF);   // 最高一字
      default: ph <= Read;
    endcase
    if (s < 3) s <= s + 1; else s <= 0;
  endrule

  rule read_ (ph == Read);
    Bit#(16) a = (s == 0) ? 16'h0000
               : ((s == 1) ? 16'h0004 : 16'h{TOP * 4 & 0xFFFF:04X});
    Bit#(32) want = (s == 0) ? 32'h{V0:08X}
                  : ((s == 1) ? 32'h{V1:08X} : 32'h{VT:08X});
    let x <- d.regs.access(RegReq {{ addr: a, write: False,
                                     wdata: 0, wstrb: 4'hF }});
    if (x.rdata != want) begin
      $display("FAIL word at %04h is %08h, want %08h", a, x.rdata, want);
      bad <= True;
    end
    if (s == 2) ph <= Strb;
    if (s < 2) s <= s + 1; else s <= 0;
  endrule

  // 只选第 1 个字节：其余三个字节必须原封不动
  rule strb (ph == Strb);
    wr(16'h0000, 32'h0000FF00, 4'b0010);
    ph <= StrbCheck;
  endrule

  rule strbCheck (ph == StrbCheck);
    let x <- d.regs.access(RegReq {{ addr: 16'h0000, write: False,
                                     wdata: 0, wstrb: 4'hF }});
    Bit#(32) want = (32'h{V0:08X} & 32'hFFFF00FF) | 32'h0000FF00;
    if (x.rdata != want) begin
      $display("FAIL byte strobe wrote %08h, want %08h", x.rdata, want);
      bad <= True;
    end
    ph <= Done;
  endrule

  rule fin (ph == Done);
    if (bad) $display("FAILED");
    else $display("PASS sram: words go in and out, the top word included, "
                  + "and a byte strobe touches one byte");
    $finish(bad ? 1 : 0);
  endrule
endmodule

endpackage
'''

(out / f"Sram{label}Tb.bsv").write_text(txt, encoding="utf-8")
print(f"  sram 行为测试台就位：words={words}")
