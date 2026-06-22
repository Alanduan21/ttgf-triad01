/*
 * Copyright (c) 2024 Duan Yihe
 * SPDX-License-Identifier: Apache-2.0
 * project.v — TRIAD01 Top Level
 * TinyTapeout GF180nm submission
 *
 * Clocked failsafe decision block for autonomous drones.
 * Evaluates RC and FC health signals using temporal filtering
 * and ternary inference to select: PRIMARY / FALLBACK / SAFE_HOLD
 *
 * Pin assignments:
 *
 * INPUTS
 *   ui[0]  fc_live      FC heartbeat present
 *   ui[1]  rc_live      RC signal present
 *   ui[2]  fc_conf      FC confidence qualifier
 *   ui[3]  rc_conf      RC confidence qualifier
 *   ui[4]  scan_in      Scan chain serial input (Scan mode only)
 *   ui[5]  reserved     tie low
 *   ui[6]  mode[0]      Mode select LSB
 *   ui[7]  mode[1]      Mode select MSB
 *
 * OUTPUTS
 *   uo[0]  decision[0]      LSB of arbitration decision
 *   uo[1]  decision[1]      MSB of arbitration decision
 *   uo[2]  decision_valid   Output has stabilised
 *   uo[3]  fc_score[0]      Debug: FC health score LSB
 *   uo[4]  fc_score[1]      Debug: FC health score MSB
 *   uo[5]  rc_score[0]      Debug: RC health score LSB
 *   uo[6]  rc_score[1]      Debug: RC health score MSB
 *   uo[7]  pwm_out / loopback
 *          Normal:   50 Hz PWM servo signal
 *          PWM test: direct copy of ui[0]
 *
 * BIDIR (all outputs)
 *   uio[0]  safehold_active   HIGH when decision == SAFE_HOLD
 *   uio[1]  scan_out          Scan chain serial output
 *   uio[2]  bist_done         LBIST completed
 *   uio[3]  bist_pass         LBIST pass (update GOLDEN_SIG first)
 *   uio[4]  raw_decision[0]   Pre-hysteresis debug
 *   uio[5]  raw_decision[1]   Pre-hysteresis debug
 *   uio[6]  reserved          0
 *   uio[7]  reserved          0
 *
 * Decision encoding:
 *   2'b10 = PRIMARY    RC controls  → PWM neutral (1.5 ms)
 *   2'b01 = FALLBACK   FC controls  → PWM neutral (1.5 ms)
 *   2'b00 = SAFE_HOLD  freeze/kill  → PWM minimum (1.0 ms)
 */

`default_nettype none

module tt_um_Alanduan21_triad01_top (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // ── Mode select ──────────────────────────────────────────────
  wire [1:0] mode = ui_in[7:6];
  localparam MODE_LOOPBACK = 2'b01;
  localparam MODE_SCAN     = 2'b10;
  localparam MODE_LBIST    = 2'b11;

  // ── TRIAD-SAFE inputs ─────────────────────────────────────────
  wire fc_live = ui_in[0];
  wire rc_live = ui_in[1];
  wire fc_conf = ui_in[2];
  wire rc_conf = ui_in[3];

  // ── Internal wires ────────────────────────────────────────────
  wire [1:0] fc_score, rc_score;
  wire [3:0] fc_cnt_w, rc_cnt_w;
  wire [1:0] raw_decision, decision;
  wire       decision_valid, safehold_active;
  wire       pwm_out_sig;

  // ── TRIAD-SAFE ────────────────────────────────────────────────
  triad01_input_filter u_filter (
      .clk        (clk),
      .rst_n      (rst_n),
      .fc_live    (fc_live),
      .rc_live    (rc_live),
      .fc_conf    (fc_conf),
      .rc_conf    (rc_conf),
      .fc_score   (fc_score),
      .rc_score   (rc_score),
      .fc_cnt_out (fc_cnt_w),
      .rc_cnt_out (rc_cnt_w)
  );

  triad01_arbitration_engine u_engine (
      .fc_score     (fc_score),
      .rc_score     (rc_score),
      .raw_decision (raw_decision)
  );

  triad01_decision_fsm u_fsm (
      .clk             (clk),
      .rst_n           (rst_n),
      .raw_decision    (raw_decision),
      .decision        (decision),
      .decision_valid  (decision_valid),
      .safehold_active (safehold_active)
  );

  // ── PWM generator ─────────────────────────────────────────────
  wire [16:0] pulse_width = safehold_active ? 17'd10000 : 17'd15000;

  triad01_pwm_gen u_pwm_gen (
      .clk         (clk),
      .rst_n       (rst_n),
      .pulse_width (pulse_width),
      .pwm_out     (pwm_out_sig)
  );

  // ── DFT: scan chain ───────────────────────────────────────────
  wire scan_en = (mode == MODE_SCAN);
  wire scan_in = ui_in[4];
  wire scan_out;

  triad01_scan_chain u_scan (
      .clk        (clk),
      .rst_n      (rst_n),
      .scan_en    (scan_en),
      .scan_in    (scan_in),
      .scan_out   (scan_out),
      .fc_cnt     (fc_cnt_w),
      .rc_cnt     (rc_cnt_w),
      .fc_cnt_obs (),
      .rc_cnt_obs ()
  );

  // ── DFT: LBIST ────────────────────────────────────────────────
  wire bist_en = (mode == MODE_LBIST);
  wire bist_done, bist_pass;
  wire bist_fc_live, bist_rc_live, bist_fc_conf, bist_rc_conf;

  triad01_lbist u_lbist (
      .clk          (clk),
      .rst_n        (rst_n),
      .bist_en      (bist_en),
      .dut_out      (uo_out),
      .bist_fc_live (bist_fc_live),
      .bist_rc_live (bist_rc_live),
      .bist_fc_conf (bist_fc_conf),
      .bist_rc_conf (bist_rc_conf),
      .bist_done    (bist_done),
      .bist_pass    (bist_pass)
  );

  // ── Output assignments ────────────────────────────────────────
  assign uo_out[0] = decision[0];
  assign uo_out[1] = decision[1];
  assign uo_out[2] = decision_valid;
  assign uo_out[3] = fc_score[0];
  assign uo_out[4] = fc_score[1];
  assign uo_out[5] = rc_score[0];
  assign uo_out[6] = rc_score[1];
  assign uo_out[7] = (mode == MODE_LOOPBACK) ? ui_in[0] : pwm_out_sig;

  assign uio_out[0] = safehold_active;
  assign uio_out[1] = scan_out;
  assign uio_out[2] = bist_done;
  assign uio_out[3] = bist_pass;
  assign uio_out[4] = raw_decision[0];
  assign uio_out[5] = raw_decision[1];
  assign uio_out[6] = 1'b0;
  assign uio_out[7] = 1'b0;
  assign uio_oe     = 8'hFF;

  // Suppress unused warnings
  wire _unused = &{ena, uio_in, ui_in[5],
                   bist_fc_live, bist_rc_live, bist_fc_conf, bist_rc_conf,
                   1'b0};

endmodule