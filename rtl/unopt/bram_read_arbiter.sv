/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/bram_read_arbiter.sv
 *
 * Description: Time-multiplexed arbiter for shared BRAM read port.
 *              Static priority: pyramid_builder > frame_warper > pixel_sequencer
 *              (Only one active per FSM state, so priority doesn't matter in practice)
 */

`timescale 1ns / 1ps

module bram_read_arbiter #(
    parameter int ADDR_WIDTH = 18,
    parameter int DATA_WIDTH = 8
) (
    // BRAM interface (to memory)
    output logic [ADDR_WIDTH-1:0] bram_addr,
    output logic                  bram_re,
    input  logic [DATA_WIDTH-1:0] bram_data,

    // Requester 0 (pyramid builder - highest priority during BUILD states)
    input  logic [ADDR_WIDTH-1:0] req0_addr,
    input  logic                  req0_re,
    output logic [DATA_WIDTH-1:0] req0_data,

    // Requester 1 (frame warper - active during WARP states)
    input  logic [ADDR_WIDTH-1:0] req1_addr,
    input  logic                  req1_re,
    output logic [DATA_WIDTH-1:0] req1_data,

    // Requester 2 (pixel sequencer - active during SOLVE states)
    input  logic [ADDR_WIDTH-1:0] req2_addr,
    input  logic                  req2_re,
    output logic [DATA_WIDTH-1:0] req2_data
);

    // Static priority mux (only one requester active per state)
    always_comb begin
        if (req0_re) begin
            bram_addr = req0_addr;
            bram_re   = 1'b1;
        end else if (req1_re) begin
            bram_addr = req1_addr;
            bram_re   = 1'b1;
        end else if (req2_re) begin
            bram_addr = req2_addr;
            bram_re   = 1'b1;
        end else begin
            bram_addr = '0;
            bram_re   = 1'b0;
        end
    end

    // Broadcast data to all requesters (they check the respective `re` for valid)
    assign req0_data = bram_data;
    assign req1_data = bram_data;
    assign req2_data = bram_data;

endmodule : bram_read_arbiter
