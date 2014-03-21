#! /usr/bin/python

import empty
from opcodes import *
from memory_map import mem_map
from branching_flags import *

bench_dir  = "Array_Scalar"
bench_file = "array_scalar"
bench_name = bench_dir + "/" + bench_file
SIMD_bench_name = bench_dir + "/" + "SIMD_" + bench_file

# Get empty instances with default parameters
empty = empty.assemble_all()

def assemble_PC():
    # Nothing to do here.
    PC = empty["PC"]
    PC.file_name = bench_name
    return PC

def assemble_A():
    A = empty["A"]
    A.file_name = bench_name
    A.P("A_IO", mem_map["A"]["IO_base"])
    A.A(0)
    A.L(0)
    A.L(1),     A.N("one")
    A.L(-1),    A.N("minus_one")
    # Placeholders for branch table entries
    A.L(0),     A.N("jmp0")
    A.L(0),     A.N("jmp0a")
    A.L(0),     A.N("jmp1")
    A.L(0),     A.N("jmp2")
    A.L(0),     A.N("jmp3")
    return A

def assemble_B():
    B = empty["B"]
    B.file_name = bench_name
    B.P("B_IO", mem_map["B"]["IO_base"])
    B.P("loop_pointer",     mem_map["B"]["PO_INC_base"],     write_addr = mem_map["H"]["PO_INC_base"])
    B.A(0)
    B.L(0)
    B.L(10),    B.N("loop_count_init")
    B.L(0),     B.N("loop_count")
    B.L(0),     B.N("temp")
    B.L(0),     B.N("array")
    B.L(1)
    B.L(2)
    B.L(3)
    B.L(4)
    B.L(5)
    B.L(6)
    B.L(7)
    B.L(8)
    B.L(9)
    B.L(-1)
    # Placeholders for programmed offset
    B.L(0),     B.N("loop_pointer_init")
    return B

def assemble_I(PC, A, B):
    I = empty["I"]
    I.file_name = bench_name

# How would MIPS do it? Ideal case: no load or branch delay slots, full result forwarding
#
# init:         ADD     loop_count, loop_count_init, 0
# outer:        ADD     loop_pointer, loop_pointer_init, 0
# inner:        LW      temp, loop_pointer
#               BLTZ    break, temp
#               ADD     temp, temp, 1
#               SW      temp, loop_pointer
#               ADD     loop_pointer, loop_pointer, 1
#               JMP     inner
# break:        SUB     loop_count, loop_count, 1
#               BGTZ    outer, loop_count
#               ADD     loop_pointer, loop_pointer_init, 0
# output:       LW      temp, loop_pointer
#               BLTZ    init, temp
#               SW      temp, output_port
#               ADD     loop_pointer, loop_pointer, 1
#               JMP     output

    # Thread 0 has implicit first NOP from pipeline, so starts at 1
    # All threads start at 1, to avoid triggering branching unit at 0.
    I.A(1)

    # Instructions to fill branch table
    branch_base_addr = mem_map["BO"]["Origin"]
    branch_depth     = mem_map["BO"]["Depth"]
    I.I(ADD, branch_base_addr,                      "jmp0", 0)
    I.I(ADD, branch_base_addr +  branch_depth,      "jmp1", 0)
    I.I(ADD, branch_base_addr + (branch_depth * 2), "jmp2", 0)
    I.I(ADD, branch_base_addr + (branch_depth * 3), "jmp3", 0)


# Overhead version
#    PO_base_addr = mem_map["BPO"]["Origin"] 
#    I.I(ADD, branch_base_addr, "jmp0", 0),              I.N("init")                     # init:         ADD     loop_count, loop_count_init, 0
#    I.I(ADD, "loop_count", 0, "loop_count_init")                                        # !!! ^^^
#    I.I(ADD, PO_base_addr, 0, "loop_pointer_init"),     I.N("outer")                    # outer:        ADD     loop_pointer, loop_pointer_init, 0
#    I.NOP(),                                            I.N("inner1")                   # !!!
#    I.I(ADD, "temp", 0, "loop_pointer"),                I.N("inner2")                   # inner:        LW      temp, loop_pointer
#    I.NOP(),                                            I.JNE("break", None, "jmp0")    #               BLTZ    break, temp
#    I.I(ADD, "temp", "one", "temp")                                                     #               ADD     temp, temp, 1
#    I.I(ADD, "loop_pointer", 0, "temp")                                                 #               SW      temp, loop_pointer
#    I.NOP()                                                                             #               ADD     loop_pointer, loop_pointer, 1
#    I.NOP(),                                            I.JMP("inner2", "jmp1")         #               JMP     inner
#    I.I(ADD, "loop_count", "minus_one", "loop_count"),  I.N("break")                    # break:        SUB     loop_count, loop_count, 1
#    I.NOP(),                                            I.JNZ("outer", None, "jmp2")    #               BGTZ    outer, loop_count  
#    I.I(ADD, PO_base_addr, 0, "loop_pointer_init")                                      #               ADD     loop_pointer, loop_pointer_init, 0
#    I.I(ADD, branch_base_addr, "jmp0a", 0)                                              # !!!
#    I.I(ADD, "temp", 0, "loop_pointer"),                I.N("output")                   # output:       LW      temp, loop_pointer
#    I.NOP(),                                            I.JNE("init", None, "jmp3")     #               BLTZ    init, temp
#    I.I(ADD, "A_IO", 0, "temp")                                                         #               SW      temp, output_port
#    I.NOP()                                                                             #               ADD     loop_pointer, loop_pointer, 1
#    I.NOP(),                                            I.JMP("output", "jmp0a")        #               JMP     output

# Experiment:
# Code size: 19 instructions
# 34 passes over array of 10 elements, 10 times, over 200,000 simulation cycles
# Cycles: 194792 - 40 = 194752
# Useful cycles: 194752 / 8 = 24344
# Cycles per pass: 24344 / 34 = 716

# Efficient version
    PO_base_addr = mem_map["BPO"]["Origin"] 
    I.I(ADD, branch_base_addr, "jmp0", 0),              I.N("init")
    I.I(ADD, "loop_count", 0, "loop_count_init")
    I.I(ADD, PO_base_addr, 0, "loop_pointer_init"),     I.N("outer") # un-branched-to
    I.NOP(),                                            I.N("inner1")
    I.I(ADD, "temp", 0, "loop_pointer"),                I.N("inner2")
    I.I(ADD, "temp", "one", "temp"),                    I.JNE("break", False, "jmp0")
    I.I(ADD, "loop_pointer", 0, "temp"),                I.JMP("inner2", "jmp1")
    I.I(ADD, "loop_count", "minus_one", "loop_count"),  I.N("break")
    I.I(ADD, PO_base_addr, 0, "loop_pointer_init"),     I.JNZ("inner1", None, "jmp2")
    I.I(ADD, branch_base_addr, "jmp0a", 0)
    I.I(ADD, "temp", 0, "loop_pointer"),                I.N("output")
    I.I(ADD, "A_IO", 0, "temp"),                        I.N("output2"), I.JNE("init", False, "jmp3"), I.JPO("output", None, "jmp0a")
    #I.I(ADD, "loop_pointer", 0, "temp"),                I.N("output2"), I.JNE("init", False, "jmp3")
    #I.I(ADD, "temp", 0, "loop_pointer"),                I.JMP("output2", "jmp0a")

# Experiment:
# Code size: 12 instructions
# 66 passes over array of 10 elements, 10 times, over 200,000 simulation cycles
# Cycles: 198568 - 40 = 198528
# Useful cycles: 198528 / 8 = 24816
# Cycles per pass: 24816 / 66 = 376

# Speedup relative to MIPS equivalent: 716 / 376 = 1.904x (or +47%)

# Overhead Unrolled
#    PO_base_addr = mem_map["BPO"]["Origin"] 
#    I.I(ADD, PO_base_addr, 0, "loop_pointer_init"),     I.N("outer")                    # outer:        ADD     loop_pointer, loop_pointer_init, 0
#    I.NOP(),                                            I.N("inner1")                   # !!!
#    I.I(ADD, "temp", 0, "loop_pointer"),                I.N("inner2")                   # inner:        LW      temp, loop_pointer
#    I.I(ADD, "temp", "one", "temp")                                                     #               ADD     temp, temp, 1
#    I.I(ADD, PO_base_addr, 0, "loop_pointer_init")                                      #               ADD     loop_pointer, loop_pointer_init, 0
#    I.I(ADD, "loop_pointer", 0, "temp")                                                 #               SW      temp, loop_pointer
#    I.NOP()                                                                             #               ADD     loop_pointer, loop_pointer, 1



    # Resolve jumps
    I.resolve_forward_jumps()

    # Set programmed offsets
    read_PO  = (mem_map["B"]["Depth"] - mem_map["B"]["PO_INC_base"] + B.R("array")) & 0x3FF
    write_PO = (mem_map["H"]["Origin"] + mem_map["H"]["Depth"] - mem_map["H"]["PO_INC_base"] + B.W("array")) & 0xFFF
    PO = (1 << 34) | (1 << 32) | (write_PO << 20) | read_PO
    B.A(B.R("loop_pointer_init"))
    B.L(PO)
    # Since the next indirect memory address is one further down
    #read_PO -= 1
    #write_PO -= 1
    #PO = (1 << 34) | (1 << 32) | (write_PO << 20) | read_PO
    #B.A(B.R("output_pointer_init"))
    #B.L(PO)

    return I

# Leave these all zero for now: only zero-based thread will do something, all
# others will hang at 0 due to empty branch tables.

def assemble_XDO():
    ADO, BDO, DDO = empty["ADO"], empty["BDO"], empty["DDO"]
    ADO.file_name = bench_name
    BDO.file_name = bench_name
    DDO.file_name = bench_name
    return ADO, BDO, DDO

def assemble_XPO():
    APO, BPO, DPO = empty["APO"], empty["BPO"], empty["DPO"]
    APO.file_name = bench_name
    BPO.file_name = bench_name
    DPO.file_name = bench_name
    return APO, BPO, DPO

def assemble_XIN():
    AIN, BIN, DIN = empty["AIN"], empty["BIN"], empty["DIN"]
    AIN.file_name = bench_name
    BIN.file_name = bench_name
    DIN.file_name = bench_name
    return AIN, BIN, DIN

def assemble_branches():
    BO, BD, BC, BP, BPE = empty["BO"], empty["BD"], empty["BC"], empty["BP"], empty["BPE"]
    BO.file_name = bench_name    
    BD.file_name = bench_name    
    BC.file_name = bench_name    
    BP.file_name = bench_name    
    BPE.file_name = bench_name    
    return BO, BD, BC, BP, BPE

def assemble_all():
    PC = assemble_PC()
    A  = assemble_A()
    B  = assemble_B()
    I  = assemble_I(PC, A, B)
    ADO, BDO, DDO = assemble_XDO()
    APO, BPO, DPO = assemble_XPO()
    AIN, BIN, DIN = assemble_XIN()
    BO, BD, BC, BP, BPE = assemble_branches()
    hailstone = {"PC":PC, "A":A, "B":B, "I":I, 
                 "ADO":ADO, "BDO":BDO, "DDO":DDO,
                 "APO":APO, "BPO":BPO, "DPO":DPO,
                 "AIN":AIN, "BIN":BIN, "DIN":DIN,
                 "BO":BO, "BD":BD, "BC":BC, "BP":BP, "BPE":BPE}
    return hailstone

def dump_all(hailstone):
    for memory in hailstone.values():
        memory.file_dump()

if __name__ == "__main__":
    hailstone = assemble_all()
    dump_all(hailstone)

