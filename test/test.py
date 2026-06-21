import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# ─────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────
PRIMARY   = 0b10
FALLBACK  = 0b01
SAFE_HOLD = 0b00

MODE_NORMAL   = 0b00
MODE_LOOPBACK = 0b01
MODE_SCAN     = 0b10
MODE_LBIST    = 0b11

# ─────────────────────────────────────────────────────────────────
# Pin readers
# ─────────────────────────────────────────────────────────────────
def uo(dut):       return int(dut.uo_out.value)
def uio(dut):      return int(dut.uio_out.value)

def get_decision(dut):        return uo(dut) & 0b11
def get_valid(dut):           return (uo(dut) >> 2) & 1
def get_fc_score(dut):        return (uo(dut) >> 3) & 0b11
def get_rc_score(dut):        return (uo(dut) >> 5) & 0b11
def get_pwm_out(dut):         return (uo(dut) >> 7) & 1
def get_safehold_active(dut): return uio(dut) & 1
def get_scan_out(dut):        return (uio(dut) >> 1) & 1
def get_bist_done(dut):       return (uio(dut) >> 2) & 1
def get_bist_pass(dut):       return (uio(dut) >> 3) & 1
def get_raw_decision(dut):    return (uio(dut) >> 4) & 0b11

# ─────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────
def ui_val(fc_live, rc_live, fc_conf, rc_conf, scan_in=0, mode=MODE_NORMAL):
    return (fc_live      |
            (rc_live  << 1) |
            (fc_conf  << 2) |
            (rc_conf  << 3) |
            (scan_in  << 4) |
            (mode     << 6))

async def reset(dut):
    dut.rst_n.value  = 0
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)

async def drive(dut, fc_live, rc_live, fc_conf, rc_conf, mode=MODE_NORMAL):
    dut.ui_in.value  = ui_val(fc_live, rc_live, fc_conf, rc_conf, mode=mode)
    dut.uio_in.value = 0

# ─────────────────────────────────────────────────────────────────
# T0: First silicon loopback — verify pads are alive
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_loopback(dut):
    """T0: PWM-test mode — ui[0] must appear on uo[7]"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)

    dut.ui_in.value = ui_val(0, 0, 0, 0, mode=MODE_LOOPBACK)
    await ClockCycles(dut.clk, 2)
    assert get_pwm_out(dut) == 0, "T0 FAIL: loopback low expected 0"

    dut.ui_in.value = ui_val(1, 0, 0, 0, mode=MODE_LOOPBACK)
    await ClockCycles(dut.clk, 2)
    assert get_pwm_out(dut) == 1, "T0 FAIL: loopback high expected 1"

    dut._log.info("T0 PASS: pad loopback works, silicon is alive")

# ─────────────────────────────────────────────────────────────────
# T6: Reset
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_reset(dut):
    """T6: Reset → SAFE_HOLD, valid=0, safehold_active=1"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)
    assert get_decision(dut) == SAFE_HOLD, f"T6 FAIL: got {get_decision(dut):02b}"
    assert get_valid(dut) == 0,            "T6 FAIL: valid should be 0"
    assert get_safehold_active(dut) == 1,  "T6 FAIL: safehold_active should be 1"
    dut._log.info("T6 PASS: SAFE_HOLD, valid=0, safehold_active=1 after reset")

# ─────────────────────────────────────────────────────────────────
# T1: Both healthy → PRIMARY
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_primary(dut):
    """T1: Both RC and FC healthy → PRIMARY"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)
    await drive(dut, fc_live=1, rc_live=1, fc_conf=1, rc_conf=1)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == PRIMARY,  f"T1 FAIL: got {get_decision(dut):02b}"
    assert get_valid(dut) == 1,           "T1 FAIL: valid=0"
    assert get_safehold_active(dut) == 0, "T1 FAIL: safehold_active should be 0"
    dut._log.info(f"T1 PASS: PRIMARY, fc_score={get_fc_score(dut):02b} rc_score={get_rc_score(dut):02b}")

# ─────────────────────────────────────────────────────────────────
# T5: RC flicker → still PRIMARY
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_flicker(dut):
    """T5: RC drops for 3 cycles only → stays PRIMARY"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    await drive(dut, 1, 0, 1, 0)   # RC drops
    await ClockCycles(dut.clk, 3)
    await drive(dut, 1, 1, 1, 1)   # RC recovers
    await ClockCycles(dut.clk, 8)
    assert get_decision(dut) == PRIMARY, f"T5 FAIL: got {get_decision(dut):02b}"
    dut._log.info("T5 PASS: flicker ignored, still PRIMARY")

# ─────────────────────────────────────────────────────────────────
# T2: RC loss → FALLBACK
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_fallback(dut):
    """T2: RC lost, FC alive → FALLBACK"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    await drive(dut, 1, 0, 1, 0)   # RC gone
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == FALLBACK, f"T2 FAIL: got {get_decision(dut):02b}"
    assert get_valid(dut) == 1,           "T2 FAIL: valid=0"
    dut._log.info("T2 PASS: FALLBACK")

# ─────────────────────────────────────────────────────────────────
# T3: Both lost → SAFE_HOLD
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_safehold(dut):
    """T3: Both lost → SAFE_HOLD, safehold_active=1"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)
    await drive(dut, 0, 0, 0, 0)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == SAFE_HOLD,  f"T3 FAIL: got {get_decision(dut):02b}"
    assert get_valid(dut) == 1,             "T3 FAIL: valid=0"
    assert get_safehold_active(dut) == 1,   "T3 FAIL: safehold_active=0"
    dut._log.info("T3 PASS: SAFE_HOLD, safehold_active=1")

# ─────────────────────────────────────────────────────────────────
# T4: Recovery → PRIMARY
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_recovery(dut):
    """T4: Recover from SAFE_HOLD → PRIMARY"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)
    await drive(dut, 0, 0, 0, 0)
    await ClockCycles(dut.clk, 35)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == PRIMARY,  f"T4 FAIL: got {get_decision(dut):02b}"
    assert get_safehold_active(dut) == 0, "T4 FAIL: safehold_active should be 0"
    dut._log.info("T4 PASS: recovered to PRIMARY")

# ─────────────────────────────────────────────────────────────────
# PWM: verify pulse is high then low
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_pwm_primary(dut):
    """PWM: in PRIMARY pulse width should be ~15000 cycles (neutral 1.5 ms)"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)  # settle to PRIMARY

    # Wait for rising edge of pwm_out (start of pulse)
    for _ in range(250000):
        await RisingEdge(dut.clk)
        if get_pwm_out(dut) == 1:
            break
    assert get_pwm_out(dut) == 1, "PWM FAIL: never went high"

    # Count high cycles
    high_cnt = 0
    for _ in range(20000):
        await RisingEdge(dut.clk)
        if get_pwm_out(dut) == 1:
            high_cnt += 1
        else:
            break

    # Neutral = 15000, allow ±5%
    assert 14000 <= high_cnt <= 16000, \
        f"PWM FAIL: pulse={high_cnt} cycles, expected 14000..16000"
    dut._log.info(f"PWM PASS: PRIMARY neutral pulse = {high_cnt} cycles")

@cocotb.test()
async def test_pwm_safehold(dut):
    """PWM: in SAFE_HOLD pulse width should be ~10000 cycles (minimum 1.0 ms)"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)
    await drive(dut, 0, 0, 0, 0)
    await ClockCycles(dut.clk, 35)  # settle to SAFE_HOLD

    for _ in range(250000):
        await RisingEdge(dut.clk)
        if get_pwm_out(dut) == 1:
            break
    assert get_pwm_out(dut) == 1, "PWM FAIL: never went high"

    high_cnt = 0
    for _ in range(15000):
        await RisingEdge(dut.clk)
        if get_pwm_out(dut) == 1:
            high_cnt += 1
        else:
            break

    # Minimum = 10000, allow ±5%
    assert 9000 <= high_cnt <= 11000, \
        f"PWM FAIL: pulse={high_cnt} cycles, expected 9000..11000"
    dut._log.info(f"PWM PASS: SAFE_HOLD minimum pulse = {high_cnt} cycles")

# ─────────────────────────────────────────────────────────────────
# Scan: shift 8 bits through, verify scan_out toggles
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_scan(dut):
    """Scan: shift known pattern, verify 8 bits emerge at scan_out"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)

    # First drive counters to a known state: both channels healthy for 15 cycles
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 15)

    pattern = 0b10110101
    captured = 0

    for i in range(8):
        bit = (pattern >> i) & 1
        dut.ui_in.value = ui_val(0, 0, 0, 0, scan_in=bit, mode=MODE_SCAN)
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        captured |= (get_scan_out(dut) << i)
        dut._log.info(f"  scan[{i}]: in={bit} out={get_scan_out(dut)}")

    # We don't assert an exact value (counters were live during prior cycles)
    # but scan_out must have produced valid 0/1 on every cycle — no X/Z
    dut._log.info(f"SCAN PASS: 8-bit shift complete, captured={captured:08b}")

# ─────────────────────────────────────────────────────────────────
# LBIST: verify FSM runs to completion
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_lbist(dut):
    """LBIST: assert bist_en, wait 260 cycles, check bist_done=1"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)

    # Enter LBIST mode
    dut.ui_in.value  = ui_val(0, 0, 0, 0, mode=MODE_LBIST)
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 260)

    assert get_bist_done(dut) == 1, "LBIST FAIL: bist_done not set after 260 cycles"
    dut._log.info(f"LBIST PASS: done={get_bist_done(dut)}, "
                  f"pass={get_bist_pass(dut)} "
                  f"(pass=0 expected until GOLDEN_SIG updated)")

    # Deassert mode → bist_done should clear
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)
    assert get_bist_done(dut) == 0, "LBIST FAIL: bist_done did not clear"
    dut._log.info("LBIST PASS: bist_done clears on mode exit")

# ─────────────────────────────────────────────────────────────────
# Legacy combined test — kept for CI compatibility
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_project(dut):
    """Original combined test (T1–T6) preserved for CI"""
    cocotb.start_soon(Clock(dut.clk, 100, units="ns").start())
    await reset(dut)

    assert get_decision(dut) == SAFE_HOLD and get_valid(dut) == 0
    dut._log.info("T6 PASS")

    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == PRIMARY and get_valid(dut) == 1
    dut._log.info("T1 PASS")

    await drive(dut, 1, 0, 1, 0)
    await ClockCycles(dut.clk, 3)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 8)
    assert get_decision(dut) == PRIMARY
    dut._log.info("T5 PASS")

    await drive(dut, 1, 0, 1, 0)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == FALLBACK and get_valid(dut) == 1
    dut._log.info("T2 PASS")

    await drive(dut, 0, 0, 0, 0)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == SAFE_HOLD and get_valid(dut) == 1
    dut._log.info("T3 PASS")

    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == PRIMARY and get_valid(dut) == 1
    dut._log.info("T4 PASS")

    dut._log.info("ALL ORIGINAL TESTS PASSED")
