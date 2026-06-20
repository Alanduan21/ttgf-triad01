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
 *   INPUTS  ui_in[0]   fc_live       FC heartbeat present
 *           ui_in[1]   rc_live       RC signal present
 *           ui_in[2]   fc_conf       FC confidence qualifier
 *           ui_in[3]   rc_conf       RC confidence qualifier
 *           ui_in[7:4] reserved      tie low
 *
 *   OUTPUTS uo_out[0]  decision[0]   LSB of decision
 *           uo_out[1]  decision[1]   MSB of decision
 *           uo_out[2]  decision_valid output has stabilised
 *           uo_out[3]  fc_score[0]   debug: FC score LSB
 *           uo_out[4]  fc_score[1]   debug: FC score MSB
 *           uo_out[5]  rc_score[0]   debug: RC score LSB
 *           uo_out[6]  rc_score[1]   debug: RC score MSB
 *           uo_out[7]  reserved      0
 *
 *   BIDIR   uio used as outputs for raw_decision debug
 *           uio_out[1:0] raw_decision (pre-hysteresis)
 *           uio_out[7:2] reserved 0
 *
 * Decision encoding:
 *   2'b10 = PRIMARY    (RC controls)
 *   2'b01 = FALLBACK   (FC controls)
 *   2'b00 = SAFE_HOLD  (freeze outputs)
*/

`default_nettype none

module tt_um_Alanduan21_triad01_top (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // input 
  wire fc_live = ui_in[0];
  wire rc_live = ui_in[1];
  wire fc_conf = ui_in[2];
  wire rc_conf = ui_in[3];

  // internal wires
  wire [1:0] fc_score;  // 2-bit score for FC health
  wire [1:0] rc_score;  // 2-bit score for RC health
  wire [1:0] raw_decision; // pre-hysteresis decision
  wire decision_valid; // indicates when the decision is stable

  // module instatiations
  triad01_input_filter u_filter (
      .clk       (clk),
      .rst_n     (rst_n),
      .fc_live   (fc_live),
      .rc_live   (rc_live),
      .fc_conf   (fc_conf),
      .rc_conf   (rc_conf),
      .fc_score  (fc_score),
      .rc_score  (rc_score)
  );

  triad01_ternary_engine u_engine (
      .fc_score     (fc_score),
      .rc_score     (rc_score),
      .raw_decision (raw_decision)
  );
 
  triad01_decision_fsm u_fsm (
      .clk            (clk),
      .rst_n          (rst_n),
      .raw_decision   (raw_decision),
      .decision       (decision),
      .decision_valid (decision_valid)
  );


  // All output pins must be assigned. If not used, assign to 0.
  // output assignment 
  assign uo_out[0]   = decision[0];
  assign uo_out[1]   = decision[1];
  assign uo_out[2]   = decision_valid;
  assign uo_out[3]   = fc_score[0];   // debug
  assign uo_out[4]   = fc_score[1];   // debug
  assign uo_out[5]   = rc_score[0];   // debug
  assign uo_out[6]   = rc_score[1];   // debug
  assign uo_out[7]   = 1'b0;

  // bidir: drive raw_decision out for debug, all as outputs
  assign uio_out     = {6'b0, raw_decision};
  assign uio_oe      = 8'hFF;         // all bidir as outputs
 
  // Suppress unused input warnings
  wire _unused = &{ena, uio_in, ui_in[7:4], 1'b0};

endmodule
