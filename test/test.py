import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

PRIMARY   = 0b10
FALLBACK  = 0b01
SAFE_HOLD = 0b00

MODE_NORMAL   = 0b00
MODE_LOOPBACK = 0b01
MODE_SCAN     = 0b10
MODE_LBIST    = 0b11

# ─────────────────────────────────────────────────────────────────
# Pin readers
# uo_out is always fully driven — safe to int() directly.
# uio_out may have X bits (e.g. scan_out before scan mode).
# Read uio_out as a binary string and pick individual chars.
# ─────────────────────────────────────────────────────────────────
def _uo(dut):
    return int(dut.uo_out.value)

def _uio_bit(dut, n):
    """Read uio_out bit n safely: X/Z → 0."""
    s = dut.uio_out.value.binstr  # e.g. '0x00xx10' MSB first
    # binstr is MSB-first, length 8, index from right = bit n
    c = s[7 - n]
    return 1 if c == '1' else 0

def get_decision(dut):        return _uo(dut) & 0b11
def get_valid(dut):           return (_uo(dut) >> 2) & 1
def get_fc_score(dut):        return (_uo(dut) >> 3) & 0b11
def get_rc_score(dut):        return (_uo(dut) >> 5) & 0b11
def get_pwm_out(dut):         return (_uo(dut) >> 7) & 1
def get_safehold_active(dut): return _uio_bit(dut, 0)
def get_scan_out(dut):        return _uio_bit(dut, 1)
def get_bist_done(dut):       return _uio_bit(dut, 2)
def get_bist_pass(dut):       return _uio_bit(dut, 3)

# ─────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────
def ui_val(fc_live=0, rc_live=0, fc_conf=0, rc_conf=0, scan_in=0, mode=MODE_NORMAL):
    return (fc_live         |
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

async def drive(dut, fc_live=0, rc_live=0, fc_conf=0, rc_conf=0, mode=MODE_NORMAL):
    dut.ui_in.value  = ui_val(fc_live, rc_live, fc_conf, rc_conf, mode=mode)
    dut.uio_in.value = 0

# ─────────────────────────────────────────────────────────────────
# T0: Loopback
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_loopback(dut):
    """T0: PWM-test mode — ui[0] must appear directly on uo[7]"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)

    dut.ui_in.value = ui_val(fc_live=0, mode=MODE_LOOPBACK)
    await ClockCycles(dut.clk, 2)
    assert get_pwm_out(dut) == 0, "T0 FAIL: expected 0"

    dut.ui_in.value = ui_val(fc_live=1, mode=MODE_LOOPBACK)
    await ClockCycles(dut.clk, 2)
    assert get_pwm_out(dut) == 1, "T0 FAIL: expected 1"

    dut._log.info("T0 PASS: pad loopback works, silicon is alive")

# ─────────────────────────────────────────────────────────────────
# T6: Reset
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_reset(dut):
    """T6: Reset → SAFE_HOLD, valid=0"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)
    assert get_decision(dut) == SAFE_HOLD, f"T6 FAIL: got {get_decision(dut):02b}"
    assert get_valid(dut) == 0,            "T6 FAIL: valid should be 0"
    dut._log.info("T6 PASS: SAFE_HOLD, valid=0 after reset")

# ─────────────────────────────────────────────────────────────────
# T1: PRIMARY
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_primary(dut):
    """T1: Both RC and FC healthy → PRIMARY"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)
    await drive(dut, fc_live=1, rc_live=1, fc_conf=1, rc_conf=1)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == PRIMARY, f"T1 FAIL: got {get_decision(dut):02b}"
    assert get_valid(dut) == 1,          "T1 FAIL: valid=0"
    assert get_safehold_active(dut) == 0,"T1 FAIL: safehold_active should be 0"
    dut._log.info(f"T1 PASS: PRIMARY fc={get_fc_score(dut):02b} rc={get_rc_score(dut):02b}")

# ─────────────────────────────────────────────────────────────────
# T5: Flicker
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_flicker(dut):
    """T5: RC drops 3 cycles → stays PRIMARY"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    await drive(dut, fc_live=1, rc_live=0, fc_conf=1, rc_conf=0)
    await ClockCycles(dut.clk, 3)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 8)
    assert get_decision(dut) == PRIMARY, f"T5 FAIL: got {get_decision(dut):02b}"
    dut._log.info("T5 PASS: flicker ignored, still PRIMARY")

# ─────────────────────────────────────────────────────────────────
# T2: FALLBACK
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_fallback(dut):
    """T2: RC lost → FALLBACK"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    await drive(dut, fc_live=1, rc_live=0, fc_conf=1, rc_conf=0)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == FALLBACK, f"T2 FAIL: got {get_decision(dut):02b}"
    assert get_valid(dut) == 1,           "T2 FAIL: valid=0"
    dut._log.info("T2 PASS: FALLBACK")

# ─────────────────────────────────────────────────────────────────
# T3: SAFE_HOLD
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_safehold(dut):
    """T3: Both lost → SAFE_HOLD, safehold_active=1"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    await drive(dut, 0, 0, 0, 0)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == SAFE_HOLD, f"T3 FAIL: got {get_decision(dut):02b}"
    assert get_valid(dut) == 1,            "T3 FAIL: valid=0"
    assert get_safehold_active(dut) == 1,  "T3 FAIL: safehold_active=0"
    dut._log.info("T3 PASS: SAFE_HOLD, safehold_active=1")

# ─────────────────────────────────────────────────────────────────
# T4: Recovery
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_recovery(dut):
    """T4: Recover → PRIMARY"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)
    await drive(dut, 0, 0, 0, 0)
    await ClockCycles(dut.clk, 35)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == PRIMARY,  f"T4 FAIL: got {get_decision(dut):02b}"
    assert get_safehold_active(dut) == 0, "T4 FAIL: safehold_active should be 0"
    dut._log.info("T4 PASS: recovered to PRIMARY")

# ─────────────────────────────────────────────────────────────────
# PWM
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_pwm_primary(dut):
    """PWM: PRIMARY → neutral ~15000 cycles"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)

    for _ in range(250000):
        await RisingEdge(dut.clk)
        if get_pwm_out(dut) == 1:
            break
    assert get_pwm_out(dut) == 1, "PWM FAIL: never went high"

    high_cnt = 0
    for _ in range(20000):
        await RisingEdge(dut.clk)
        if get_pwm_out(dut) == 1:
            high_cnt += 1
        else:
            break

    assert 14000 <= high_cnt <= 16000, f"PWM FAIL: {high_cnt} cycles"
    dut._log.info(f"PWM PASS: PRIMARY neutral = {high_cnt} cycles")

@cocotb.test()
async def test_pwm_safehold(dut):
    """PWM: SAFE_HOLD → minimum ~10000 cycles"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    await drive(dut, 0, 0, 0, 0)
    await ClockCycles(dut.clk, 35)

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

    assert 9000 <= high_cnt <= 11000, f"PWM FAIL: {high_cnt} cycles"
    dut._log.info(f"PWM PASS: SAFE_HOLD minimum = {high_cnt} cycles")

# ─────────────────────────────────────────────────────────────────
# Scan
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_scan(dut):
    """Scan: shift pattern, verify bits emerge at scan_out"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 15)

    pattern = 0b10110101
    captured = 0
    for i in range(8):
        bit = (pattern >> i) & 1
        dut.ui_in.value  = ui_val(scan_in=bit, mode=MODE_SCAN)
        dut.uio_in.value = 0
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        out = get_scan_out(dut)
        captured |= (out << i)
        dut._log.info(f"  scan[{i}]: in={bit} out={out}")

    dut._log.info(f"SCAN PASS: captured={captured:08b}")

# ─────────────────────────────────────────────────────────────────
# LBIST
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_lbist(dut):
    """LBIST: enter LBIST mode, wait 300 cycles, check bist_done=1"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)
    dut.ui_in.value  = ui_val(mode=MODE_LBIST)
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 300)
    dut._log.info(f"MISR = 0x{int(dut.triad01_lbist.misr.value):04X}")
    assert get_bist_done(dut) == 1, "LBIST FAIL: bist_done not set after 300 cycles"
    dut._log.info(f"LBIST PASS: done=1 pass={get_bist_pass(dut)}")
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)
    assert get_bist_done(dut) == 0, "LBIST FAIL: bist_done did not clear"
    dut._log.info("LBIST PASS: clears on mode exit")
    dut._log.info(f"MISR = 0x{int(dut.triad01_lbist.misr.value):04X}")

# ─────────────────────────────────────────────────────────────────
# Legacy combined — CI
# ─────────────────────────────────────────────────────────────────
@cocotb.test()
async def test_project(dut):
    """Original T1–T6 combined test"""
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    await reset(dut)

    assert get_decision(dut) == SAFE_HOLD and get_valid(dut) == 0
    dut._log.info("T6 PASS")

    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 35)
    assert get_decision(dut) == PRIMARY and get_valid(dut) == 1
    dut._log.info("T1 PASS")

    await drive(dut, fc_live=1, rc_live=0, fc_conf=1, rc_conf=0)
    await ClockCycles(dut.clk, 3)
    await drive(dut, 1, 1, 1, 1)
    await ClockCycles(dut.clk, 8)
    assert get_decision(dut) == PRIMARY
    dut._log.info("T5 PASS")

    await drive(dut, fc_live=1, rc_live=0, fc_conf=1, rc_conf=0)
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