import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Decision encoding
PRIMARY   = 0b10
FALLBACK  = 0b01
SAFE_HOLD = 0b00

def get_decision(dut):
    """Extract decision[1:0] from uo_out[1:0]"""
    return int(dut.uo_out.value) & 0b11

def get_valid(dut):
    """Extract decision_valid from uo_out[2]"""
    return (int(dut.uo_out.value) >> 2) & 1

async def set_inputs(dut, fc_live, rc_live, fc_conf, rc_conf):
    val = (fc_live) | (rc_live << 1) | (fc_conf << 2) | (rc_conf << 3)
    dut.ui_in.value = val
    dut.uio_in.value = 0

async def reset(dut):
    dut.rst_n.value = 0
    dut.ena.value   = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

@cocotb.test()
async def test_project(dut):
    """TRIAD01 full functional test"""

    # Start clock at 10MHz (100ns period)
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())

    # -------------------------------------------------------
    # T6: Reset — expect SAFE_HOLD, not valid
    # -------------------------------------------------------
    dut._log.info("T6: Reset behaviour")
    await reset(dut)
    assert get_decision(dut) == SAFE_HOLD, \
        f"T6 FAIL: expected SAFE_HOLD after reset, got {get_decision(dut):02b}"
    assert get_valid(dut) == 0, \
        f"T6 FAIL: expected valid=0 after reset, got {get_valid(dut)}"
    dut._log.info("T6 PASS: SAFE_HOLD, valid=0 after reset")

    # -------------------------------------------------------
    # T1: Both healthy → PRIMARY
    # Need ~25 cycles: 15 to fill counters + 8 FSM hysteresis + margin
    # -------------------------------------------------------
    dut._log.info("T1: Both RC and FC healthy -> PRIMARY")
    await set_inputs(dut, fc_live=1, rc_live=1, fc_conf=1, rc_conf=1)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == PRIMARY, \
        f"T1 FAIL: expected PRIMARY(10), got {get_decision(dut):02b}"
    assert get_valid(dut) == 1, \
        f"T1 FAIL: expected valid=1, got {get_valid(dut)}"
    dut._log.info(f"T1 PASS: decision={get_decision(dut):02b} valid={get_valid(dut)}")

    # -------------------------------------------------------
    # T5: RC flicker (3 cycles only) — should stay PRIMARY
    # -------------------------------------------------------
    dut._log.info("T5: RC flicker 3 cycles -> still PRIMARY")
    await set_inputs(dut, fc_live=1, rc_live=0, fc_conf=1, rc_conf=0)
    await ClockCycles(dut.clk, 3)
    await set_inputs(dut, fc_live=1, rc_live=1, fc_conf=1, rc_conf=1)
    await ClockCycles(dut.clk, 8)
    assert get_decision(dut) == PRIMARY, \
        f"T5 FAIL: expected PRIMARY after flicker, got {get_decision(dut):02b}"
    dut._log.info(f"T5 PASS: decision={get_decision(dut):02b} (flicker ignored)")

    # -------------------------------------------------------
    # T2: RC loss — RC drops, FC alive → FALLBACK
    # -------------------------------------------------------
    dut._log.info("T2: RC loss -> FALLBACK")
    await set_inputs(dut, fc_live=1, rc_live=0, fc_conf=1, rc_conf=0)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == FALLBACK, \
        f"T2 FAIL: expected FALLBACK(01), got {get_decision(dut):02b}"
    assert get_valid(dut) == 1, \
        f"T2 FAIL: expected valid=1, got {get_valid(dut)}"
    dut._log.info(f"T2 PASS: decision={get_decision(dut):02b} valid={get_valid(dut)}")

    # -------------------------------------------------------
    # T3: Both lost → SAFE_HOLD
    # -------------------------------------------------------
    dut._log.info("T3: Both lost -> SAFE_HOLD")
    await set_inputs(dut, fc_live=0, rc_live=0, fc_conf=0, rc_conf=0)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == SAFE_HOLD, \
        f"T3 FAIL: expected SAFE_HOLD(00), got {get_decision(dut):02b}"
    assert get_valid(dut) == 1, \
        f"T3 FAIL: expected valid=1, got {get_valid(dut)}"
    dut._log.info(f"T3 PASS: decision={get_decision(dut):02b} valid={get_valid(dut)}")

    # -------------------------------------------------------
    # T4: RC recovers → PRIMARY
    # -------------------------------------------------------
    dut._log.info("T4: RC recovers -> PRIMARY")
    await set_inputs(dut, fc_live=1, rc_live=1, fc_conf=1, rc_conf=1)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == PRIMARY, \
        f"T4 FAIL: expected PRIMARY(10), got {get_decision(dut):02b}"
    assert get_valid(dut) == 1, \
        f"T4 FAIL: expected valid=1, got {get_valid(dut)}"
    dut._log.info(f"T4 PASS: decision={get_decision(dut):02b} valid={get_valid(dut)}")

    dut._log.info("ALL TESTS PASSED")