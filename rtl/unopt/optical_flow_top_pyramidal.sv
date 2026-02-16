/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/optical_flow_top_pyramidal.sv
 *
 * Description: Top-level 3-level pyramidal Lucas-Kanade accelerator.
 *              Integrates FSM, frame memories, pyramid builder, and L-K solver. Unoptimized.
 */

`timescale 1ns / 1ps

module optical_flow_top_pyramidal #(
    parameter int IMAGE_WIDTH  = 320,
    parameter int IMAGE_HEIGHT = 240,
    parameter int PIXEL_WIDTH  = 8,
    parameter int GRAD_WIDTH   = 12,
    parameter int ACCUM_WIDTH  = 32,
    parameter int FLOW_WIDTH   = 16,
    parameter int WINDOW_SIZE  = 5
) (
    input logic clk,
    input logic rst_n,

    // Control interface
    input  logic start,
    output logic busy,
    output logic done,

    // Streaming pixel inputs (replaces frame buffer)
    input logic [PIXEL_WIDTH-1:0] pixel_curr,
    input logic [PIXEL_WIDTH-1:0] pixel_prev,
    input logic                   pixel_valid,

    // Flow output (final level only, streaming)
    output logic signed [FLOW_WIDTH-1:0] flow_u,
    output logic signed [FLOW_WIDTH-1:0] flow_v,
    output logic                         flow_valid
);

    // Pyramid dimensions
    localparam int L0_WIDTH = 80;
    localparam int L0_HEIGHT = 60;
    localparam int L1_WIDTH = 160;
    localparam int L1_HEIGHT = 120;
    localparam int L2_WIDTH = IMAGE_WIDTH;
    localparam int L2_HEIGHT = IMAGE_HEIGHT;

    /*
    * Streaming Pixel Interface
    *
    * Frame buffer removed - pixels now driven by external source (testbench, camera, etc.)
    * Pyramid builder consumes pixels at input rate (320×240 = 76,800 cycles worst case)
    */

    /*
    logic [PIXEL_WIDTH-1:0] pixel_curr_stream, pixel_prev_stream;
    logic pixel_stream_valid;
    logic frame_buffer_done;

    frame_buffer_simple #(
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) u_frame_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .pixel_curr(pixel_curr_stream),
        .pixel_prev(pixel_prev_stream),
        .pixel_valid(pixel_stream_valid),
        .frame_done(frame_buffer_done)
    );
    */

    /*
    * Pyramid Control FSM
    */
    logic pyramid_build_start, pyramid_build_done;
    logic lk_solve_start, lk_solve_done;
    logic [1:0] lk_level;
    logic upsample_start, upsample_done;
    logic [1:0] upsample_level;
    logic warp_start, warp_done;
    logic [1:0] warp_level;
    logic accum_start, accum_done;
    logic [1:0] accum_level;
    logic [3:0] fsm_state;

    pyramid_control_fsm #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) u_fsm (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .current_state(fsm_state),
        .pyramid_build_start(pyramid_build_start),
        .pyramid_build_done(pyramid_build_done),
        .lk_solve_start(lk_solve_start),
        .lk_solve_done(lk_solve_done),
        .lk_level(lk_level),
        .upsample_start(upsample_start),
        .upsample_done(upsample_done),
        .upsample_level(upsample_level),
        .warp_start(warp_start),
        .warp_done(warp_done),
        .warp_level(warp_level),
        .accum_start(accum_start),
        .accum_done(accum_done),
        .accum_level(accum_level)
    );

    /*
    * Pyramid Builder
    */
    logic [PIXEL_WIDTH-1:0] pyr_l0_curr_data, pyr_l0_prev_data;
    logic [15:0] pyr_l0_curr_addr, pyr_l0_prev_addr;
    logic pyr_l0_curr_we, pyr_l0_prev_we;

    logic [PIXEL_WIDTH-1:0] pyr_l1_curr_data, pyr_l1_prev_data;
    logic [16:0] pyr_l1_curr_addr, pyr_l1_prev_addr;
    logic pyr_l1_curr_we, pyr_l1_prev_we;

    logic [PIXEL_WIDTH-1:0] pyr_l2_curr_data, pyr_l2_prev_data;
    logic [17:0] pyr_l2_curr_addr, pyr_l2_prev_addr;
    logic pyr_l2_curr_we, pyr_l2_prev_we;

    // Current frame pyramid builder
    pyramid_builder #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .L2_WIDTH   (L2_WIDTH),
        .L2_HEIGHT  (L2_HEIGHT),
        .L1_WIDTH   (L1_WIDTH),
        .L1_HEIGHT  (L1_HEIGHT),
        .L0_WIDTH   (L0_WIDTH),
        .L0_HEIGHT  (L0_HEIGHT)
    ) u_pyramid_curr (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(pixel_curr),
        .pixel_valid(pixel_valid),
        .start(pyramid_build_start),
        .done(pyramid_build_done),  // Shared done (both frames finish simultaneously)
        .pyr_l0_data(pyr_l0_curr_data),
        .pyr_l0_addr(pyr_l0_curr_addr),
        .pyr_l0_we(pyr_l0_curr_we),
        .pyr_l1_data(pyr_l1_curr_data),
        .pyr_l1_addr(pyr_l1_curr_addr),
        .pyr_l1_we(pyr_l1_curr_we),
        .pyr_l2_data(pyr_l2_curr_data),
        .pyr_l2_addr(pyr_l2_curr_addr),
        .pyr_l2_we(pyr_l2_curr_we)
    );

    // Previous frame pyramid builder (parallel construction)
    pyramid_builder #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .L2_WIDTH   (L2_WIDTH),
        .L2_HEIGHT  (L2_HEIGHT),
        .L1_WIDTH   (L1_WIDTH),
        .L1_HEIGHT  (L1_HEIGHT),
        .L0_WIDTH   (L0_WIDTH),
        .L0_HEIGHT  (L0_HEIGHT)
    ) u_pyramid_prev (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(pixel_prev),
        .pixel_valid(pixel_valid),
        .start(pyramid_build_start),
        .done(  /* unused - use curr done */),
        .pyr_l0_data(pyr_l0_prev_data),
        .pyr_l0_addr(pyr_l0_prev_addr),
        .pyr_l0_we(pyr_l0_prev_we),
        .pyr_l1_data(pyr_l1_prev_data),
        .pyr_l1_addr(pyr_l1_prev_addr),
        .pyr_l1_we(pyr_l1_prev_we),
        .pyr_l2_data(pyr_l2_prev_data),
        .pyr_l2_addr(pyr_l2_prev_addr),
        .pyr_l2_we(pyr_l2_prev_we)
    );

    /*
    * Frame Memories (BRAM Storage)
    */

    // Level 0 memories (80x60 = 4800 pixels)
    logic [PIXEL_WIDTH-1:0] l0_curr_read_data, l0_prev_read_data;
    logic [15:0] l0_read_addr;
    logic l0_read_enable;

    frame_memory #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(16),
        .DEPTH     (L0_WIDTH * L0_HEIGHT)
    ) u_mem_l0_curr (
        .clk(clk),
        .addr_a(pyr_l0_curr_addr),
        .data_a(pyr_l0_curr_data),
        .we_a(pyr_l0_curr_we),
        .addr_b(l0_read_addr),
        .data_b(l0_curr_read_data),
        .re_b(l0_read_enable)
    );

    frame_memory #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(16),
        .DEPTH     (L0_WIDTH * L0_HEIGHT)
    ) u_mem_l0_prev (
        .clk(clk),
        .addr_a(pyr_l0_prev_addr),
        .data_a(pyr_l0_prev_data),
        .we_a(pyr_l0_prev_we),
        .addr_b(l0_read_addr),
        .data_b(l0_prev_read_data),
        .re_b(l0_read_enable)
    );

    // Level 1 memories (160x120 = 19200 pixels)
    logic [PIXEL_WIDTH-1:0] l1_curr_read_data, l1_prev_read_data;
    logic [16:0] l1_read_addr;
    logic l1_read_enable;

    frame_memory #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(17),
        .DEPTH     (L1_WIDTH * L1_HEIGHT)
    ) u_mem_l1_curr (
        .clk(clk),
        .addr_a(pyr_l1_curr_addr),
        .data_a(pyr_l1_curr_data),
        .we_a(pyr_l1_curr_we),
        .addr_b(l1_read_addr),
        .data_b(l1_curr_read_data),
        .re_b(l1_read_enable)
    );

    frame_memory #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(17),
        .DEPTH     (L1_WIDTH * L1_HEIGHT)
    ) u_mem_l1_prev (
        .clk(clk),
        .addr_a(pyr_l1_prev_addr),
        .data_a(pyr_l1_prev_data),
        .we_a(pyr_l1_prev_we),
        .addr_b(l1_read_addr),
        .data_b(l1_prev_read_data),
        .re_b(l1_read_enable)
    );

    // Level 2 memories (320x240 = 76800 pixels)
    logic [PIXEL_WIDTH-1:0] l2_curr_read_data, l2_prev_read_data;
    logic [17:0] l2_read_addr;
    logic l2_read_enable;

    frame_memory #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(18),
        .DEPTH     (L2_WIDTH * L2_HEIGHT)
    ) u_mem_l2_curr (
        .clk(clk),
        .addr_a(pyr_l2_curr_addr),
        .data_a(pyr_l2_curr_data),
        .we_a(pyr_l2_curr_we),
        .addr_b(l2_read_addr),
        .data_b(l2_curr_read_data),
        .re_b(l2_read_enable)
    );

    frame_memory #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(18),
        .DEPTH     (L2_WIDTH * L2_HEIGHT)
    ) u_mem_l2_prev (
        .clk(clk),
        .addr_a(pyr_l2_prev_addr),
        .data_a(pyr_l2_prev_data),
        .we_a(pyr_l2_prev_we),
        .addr_b(l2_read_addr),
        .data_b(l2_prev_read_data),
        .re_b(l2_read_enable)
    );

    /*
    * Flow Field Memories (Store u/v flow at each level)
    */

    // Level 0 flow (80x60 = 4800 flow vectors)
    logic signed [FLOW_WIDTH-1:0] l0_flow_u_write, l0_flow_v_write;
    logic signed [FLOW_WIDTH-1:0] l0_flow_u_read, l0_flow_v_read;
    logic [15:0] l0_flow_addr_write, l0_flow_addr_read;
    logic l0_flow_we, l0_flow_re;

    frame_memory #(
        .DATA_WIDTH(FLOW_WIDTH),
        .ADDR_WIDTH(16),
        .DEPTH(L0_WIDTH * L0_HEIGHT)
    ) u_mem_l0_flow_u (
        .clk(clk),
        .addr_a(l0_flow_addr_write),
        .data_a(l0_flow_u_write),
        .we_a(l0_flow_we),
        .addr_b(l0_flow_addr_read),
        .data_b(l0_flow_u_read),
        .re_b(l0_flow_re)
    );

    frame_memory #(
        .DATA_WIDTH(FLOW_WIDTH),
        .ADDR_WIDTH(16),
        .DEPTH(L0_WIDTH * L0_HEIGHT)
    ) u_mem_l0_flow_v (
        .clk(clk),
        .addr_a(l0_flow_addr_write),
        .data_a(l0_flow_v_write),
        .we_a(l0_flow_we),
        .addr_b(l0_flow_addr_read),
        .data_b(l0_flow_v_read),
        .re_b(l0_flow_re)
    );

    // Level 1 flow (160x120 = 19200 flow vectors)
    // Port A: Written by upsampler (UPSAMPLE_L0) or accumulator (ACCUM_L1)
    // Port B: Read by warper (WARP_L1) or accumulator (ACCUM_L1)
    logic signed [FLOW_WIDTH-1:0] l1_flow_u_write, l1_flow_v_write;
    logic signed [FLOW_WIDTH-1:0] l1_flow_u_read, l1_flow_v_read;
    logic [16:0] l1_flow_addr_write, l1_flow_addr_read;
    logic l1_flow_we, l1_flow_re;

    frame_memory #(
        .DATA_WIDTH(FLOW_WIDTH),
        .ADDR_WIDTH(17),
        .DEPTH(L1_WIDTH * L1_HEIGHT)
    ) u_mem_l1_flow_u (
        .clk(clk),
        .addr_a(l1_flow_addr_write),
        .data_a(l1_flow_u_write),
        .we_a(l1_flow_we),
        .addr_b(l1_flow_addr_read),
        .data_b(l1_flow_u_read),
        .re_b(l1_flow_re)
    );

    frame_memory #(
        .DATA_WIDTH(FLOW_WIDTH),
        .ADDR_WIDTH(17),
        .DEPTH(L1_WIDTH * L1_HEIGHT)
    ) u_mem_l1_flow_v (
        .clk(clk),
        .addr_a(l1_flow_addr_write),
        .data_a(l1_flow_v_write),
        .we_a(l1_flow_we),
        .addr_b(l1_flow_addr_read),
        .data_b(l1_flow_v_read),
        .re_b(l1_flow_re)
    );

    // Level 2 flow (320x240 = 76800 flow vectors)
    // Port A: Written by upsampler (UPSAMPLE_L1) or accumulator (ACCUM_L2)
    // Port B: Read by warper (WARP_L2) or accumulator (ACCUM_L2)
    logic signed [FLOW_WIDTH-1:0] l2_flow_u_write, l2_flow_v_write;
    logic signed [FLOW_WIDTH-1:0] l2_flow_u_read, l2_flow_v_read;
    logic [17:0] l2_flow_addr_write, l2_flow_addr_read;
    logic l2_flow_we, l2_flow_re;

    frame_memory #(
        .DATA_WIDTH(FLOW_WIDTH),
        .ADDR_WIDTH(18),
        .DEPTH(L2_WIDTH * L2_HEIGHT)
    ) u_mem_l2_flow_u (
        .clk(clk),
        .addr_a(l2_flow_addr_write),
        .data_a(l2_flow_u_write),
        .we_a(l2_flow_we),
        .addr_b(l2_flow_addr_read),
        .data_b(l2_flow_u_read),
        .re_b(l2_flow_re)
    );

    frame_memory #(
        .DATA_WIDTH(FLOW_WIDTH),
        .ADDR_WIDTH(18),
        .DEPTH(L2_WIDTH * L2_HEIGHT)
    ) u_mem_l2_flow_v (
        .clk(clk),
        .addr_a(l2_flow_addr_write),
        .data_a(l2_flow_v_write),
        .we_a(l2_flow_we),
        .addr_b(l2_flow_addr_read),
        .data_b(l2_flow_v_read),
        .re_b(l2_flow_re)
    );

    /*
    * Residual Flow Memories (Store solver output before accumulation)
    */

    // Level 1 residual flow (160x120 = 19200 flow vectors)
    logic signed [FLOW_WIDTH-1:0] l1_residual_u_write, l1_residual_v_write;
    logic signed [FLOW_WIDTH-1:0] l1_residual_u_read, l1_residual_v_read;
    logic [16:0] l1_residual_addr_write, l1_residual_addr_read;
    logic l1_residual_we, l1_residual_re;

    frame_memory #(
        .DATA_WIDTH(FLOW_WIDTH),
        .ADDR_WIDTH(17),
        .DEPTH(L1_WIDTH * L1_HEIGHT)
    ) u_mem_l1_residual_u (
        .clk(clk),
        .addr_a(l1_residual_addr_write),
        .data_a(l1_residual_u_write),
        .we_a(l1_residual_we),
        .addr_b(l1_residual_addr_read),
        .data_b(l1_residual_u_read),
        .re_b(l1_residual_re)
    );

    frame_memory #(
        .DATA_WIDTH(FLOW_WIDTH),
        .ADDR_WIDTH(17),
        .DEPTH(L1_WIDTH * L1_HEIGHT)
    ) u_mem_l1_residual_v (
        .clk(clk),
        .addr_a(l1_residual_addr_write),
        .data_a(l1_residual_v_write),
        .we_a(l1_residual_we),
        .addr_b(l1_residual_addr_read),
        .data_b(l1_residual_v_read),
        .re_b(l1_residual_re)
    );

    // Level 2 residual flow (320x240 = 76800 flow vectors)
    logic signed [FLOW_WIDTH-1:0] l2_residual_u_write, l2_residual_v_write;
    logic signed [FLOW_WIDTH-1:0] l2_residual_u_read, l2_residual_v_read;
    logic [17:0] l2_residual_addr_write, l2_residual_addr_read;
    logic l2_residual_we, l2_residual_re;

    frame_memory #(
        .DATA_WIDTH(FLOW_WIDTH),
        .ADDR_WIDTH(18),
        .DEPTH(L2_WIDTH * L2_HEIGHT)
    ) u_mem_l2_residual_u (
        .clk(clk),
        .addr_a(l2_residual_addr_write),
        .data_a(l2_residual_u_write),
        .we_a(l2_residual_we),
        .addr_b(l2_residual_addr_read),
        .data_b(l2_residual_u_read),
        .re_b(l2_residual_re)
    );

    frame_memory #(
        .DATA_WIDTH(FLOW_WIDTH),
        .ADDR_WIDTH(18),
        .DEPTH(L2_WIDTH * L2_HEIGHT)
    ) u_mem_l2_residual_v (
        .clk(clk),
        .addr_a(l2_residual_addr_write),
        .data_a(l2_residual_v_write),
        .we_a(l2_residual_we),
        .addr_b(l2_residual_addr_read),
        .data_b(l2_residual_v_read),
        .re_b(l2_residual_re)
    );

    /*
    * Warped Frame Memories (Store warped current frame at each level)
    */

    // Level 0 warped frame (80x60)
    logic [PIXEL_WIDTH-1:0] l0_warped_write_data, l0_warped_read_data;
    logic [15:0] l0_warped_write_addr, l0_warped_read_addr;
    logic l0_warped_we, l0_warped_re;

    frame_memory #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(16),
        .DEPTH(L0_WIDTH * L0_HEIGHT)
    ) u_mem_l0_warped (
        .clk(clk),
        .addr_a(l0_warped_write_addr),
        .data_a(l0_warped_write_data),
        .we_a(l0_warped_we),
        .addr_b(l0_warped_read_addr),
        .data_b(l0_warped_read_data),
        .re_b(l0_warped_re)
    );

    // Level 1 warped frame (160x120)
    logic [PIXEL_WIDTH-1:0] l1_warped_write_data, l1_warped_read_data;
    logic [16:0] l1_warped_write_addr, l1_warped_read_addr;
    logic l1_warped_we, l1_warped_re;

    frame_memory #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(17),
        .DEPTH     (L1_WIDTH * L1_HEIGHT)
    ) u_mem_l1_warped (
        .clk(clk),
        .addr_a(l1_warped_write_addr),
        .data_a(l1_warped_write_data),
        .we_a(l1_warped_we),
        .addr_b(l1_warped_read_addr),
        .data_b(l1_warped_read_data),
        .re_b(l1_warped_re)
    );

    // Level 2 warped frame (320x240)
    logic [PIXEL_WIDTH-1:0] l2_warped_write_data, l2_warped_read_data;
    logic [17:0] l2_warped_write_addr, l2_warped_read_addr;
    logic l2_warped_we, l2_warped_re;

    frame_memory #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(18),
        .DEPTH     (L2_WIDTH * L2_HEIGHT)
    ) u_mem_l2_warped (
        .clk(clk),
        .addr_a(l2_warped_write_addr),
        .data_a(l2_warped_write_data),
        .we_a(l2_warped_we),
        .addr_b(l2_warped_read_addr),
        .data_b(l2_warped_read_data),
        .re_b(l2_warped_re)
    );

    /*
    * Flow Memory Write Port Arbitration
    */

    // L1 flow memory write port (shared between upsampler and accumulator)
    logic signed [FLOW_WIDTH-1:0] l1_flow_u_write_upsample, l1_flow_v_write_upsample;
    logic signed [FLOW_WIDTH-1:0] l1_flow_u_write_accum, l1_flow_v_write_accum;
    logic [16:0] l1_flow_addr_write_upsample, l1_flow_addr_write_accum;
    logic l1_flow_we_upsample, l1_flow_we_accum;

    // Arbitration: Accumulator has priority (occurs after upsampling in FSM)
    always_comb begin
        if (l1_flow_we_accum) begin
            l1_flow_u_write = l1_flow_u_write_accum;
            l1_flow_v_write = l1_flow_v_write_accum;
            l1_flow_addr_write = l1_flow_addr_write_accum;
            l1_flow_we = l1_flow_we_accum;
        end else begin
            l1_flow_u_write = l1_flow_u_write_upsample;
            l1_flow_v_write = l1_flow_v_write_upsample;
            l1_flow_addr_write = l1_flow_addr_write_upsample;
            l1_flow_we = l1_flow_we_upsample;
        end
    end

    // L2 flow memory write port (shared between upsampler and accumulator)
    logic signed [FLOW_WIDTH-1:0] l2_flow_u_write_upsample, l2_flow_v_write_upsample;
    logic signed [FLOW_WIDTH-1:0] l2_flow_u_write_accum, l2_flow_v_write_accum;
    logic [17:0] l2_flow_addr_write_upsample, l2_flow_addr_write_accum;
    logic l2_flow_we_upsample, l2_flow_we_accum;

    always_comb begin
        if (l2_flow_we_accum) begin
            l2_flow_u_write = l2_flow_u_write_accum;
            l2_flow_v_write = l2_flow_v_write_accum;
            l2_flow_addr_write = l2_flow_addr_write_accum;
            l2_flow_we = l2_flow_we_accum;
        end else begin
            l2_flow_u_write = l2_flow_u_write_upsample;
            l2_flow_v_write = l2_flow_v_write_upsample;
            l2_flow_addr_write = l2_flow_addr_write_upsample;
            l2_flow_we = l2_flow_we_upsample;
        end
    end

    /*
    * Flow Upsampler Instances
    */

    // Upsampler read request signals (outputs from upsampler modules)
    logic [15:0] l0_flow_addr_read_upsample;
    logic l0_flow_re_upsample;
    logic [16:0] l1_flow_addr_read_upsample;
    logic l1_flow_re_upsample;

    // L0 -> L1 upsampler
    logic upsample_l0_start, upsample_l0_done;

    flow_upsampler #(
        .FLOW_WIDTH(FLOW_WIDTH),
        .COARSE_WIDTH(L0_WIDTH),
        .COARSE_HEIGHT(L0_HEIGHT),
        .FINE_WIDTH(L1_WIDTH),
        .FINE_HEIGHT(L1_HEIGHT),
        .COARSE_ADDR_WIDTH(16),
        .FINE_ADDR_WIDTH(17)
    ) u_upsample_l0_to_l1 (
        .clk(clk),
        .rst_n(rst_n),
        .start(upsample_l0_start),
        .done(upsample_l0_done),
        .coarse_u_data(l0_flow_u_read),
        .coarse_v_data(l0_flow_v_read),
        .coarse_addr(l0_flow_addr_read_upsample),
        .coarse_re(l0_flow_re_upsample),
        .fine_u_data(l1_flow_u_write_upsample),
        .fine_v_data(l1_flow_v_write_upsample),
        .fine_addr(l1_flow_addr_write_upsample),
        .fine_we(l1_flow_we_upsample)
    );

    // L1 -> L2 upsampler
    logic upsample_l1_start, upsample_l1_done;

    flow_upsampler #(
        .FLOW_WIDTH(FLOW_WIDTH),
        .COARSE_WIDTH(L1_WIDTH),
        .COARSE_HEIGHT(L1_HEIGHT),
        .FINE_WIDTH(L2_WIDTH),
        .FINE_HEIGHT(L2_HEIGHT),
        .COARSE_ADDR_WIDTH(17),
        .FINE_ADDR_WIDTH(18)
    ) u_upsample_l1_to_l2 (
        .clk(clk),
        .rst_n(rst_n),
        .start(upsample_l1_start),
        .done(upsample_l1_done),
        .coarse_u_data(l1_flow_u_read),
        .coarse_v_data(l1_flow_v_read),
        .coarse_addr(l1_flow_addr_read_upsample),
        .coarse_re(l1_flow_re_upsample),
        .fine_u_data(l2_flow_u_write_upsample),
        .fine_v_data(l2_flow_v_write_upsample),
        .fine_addr(l2_flow_addr_write_upsample),
        .fine_we(l2_flow_we_upsample)
    );

    // Control signals for upsamplers
    assign upsample_l0_start = upsample_start && (upsample_level == 2'b00);
    assign upsample_l1_start = upsample_start && (upsample_level == 2'b01);
    assign upsample_done = (upsample_level == 2'b00) ? upsample_l0_done : upsample_l1_done;

    /*
    * Pixel Sequencer Instances (Stream pixels from BRAM to L-K solver)
    */

    logic seq_l0_start, seq_l0_done;
    logic [15:0] seq_l0_read_addr;
    logic seq_l0_read_enable;
    logic [$clog2(L0_WIDTH)-1:0] seq_l0_pixel_x;
    logic [$clog2(L0_HEIGHT)-1:0] seq_l0_pixel_y;
    logic seq_l0_coord_valid;

    pixel_sequencer #(
        .WIDTH(L0_WIDTH),
        .HEIGHT(L0_HEIGHT),
        .ADDR_WIDTH(16)
    ) u_seq_l0 (
        .clk(clk),
        .rst_n(rst_n),
        .start(seq_l0_start),
        .done(seq_l0_done),
        .read_addr(seq_l0_read_addr),
        .read_enable(seq_l0_read_enable),
        .pixel_x(seq_l0_pixel_x),
        .pixel_y(seq_l0_pixel_y),
        .coord_valid(seq_l0_coord_valid)
    );

    logic seq_l1_start, seq_l1_done;
    logic [16:0] seq_l1_read_addr;
    logic seq_l1_read_enable;
    logic [$clog2(L1_WIDTH)-1:0] seq_l1_pixel_x;
    logic [$clog2(L1_HEIGHT)-1:0] seq_l1_pixel_y;
    logic seq_l1_coord_valid;

    pixel_sequencer #(
        .WIDTH(L1_WIDTH),
        .HEIGHT(L1_HEIGHT),
        .ADDR_WIDTH(17)
    ) u_seq_l1 (
        .clk(clk),
        .rst_n(rst_n),
        .start(seq_l1_start),
        .done(seq_l1_done),
        .read_addr(seq_l1_read_addr),
        .read_enable(seq_l1_read_enable),
        .pixel_x(seq_l1_pixel_x),
        .pixel_y(seq_l1_pixel_y),
        .coord_valid(seq_l1_coord_valid)
    );

    logic seq_l2_start, seq_l2_done;
    logic [17:0] seq_l2_read_addr;
    logic seq_l2_read_enable;
    logic [$clog2(L2_WIDTH)-1:0] seq_l2_pixel_x;
    logic [$clog2(L2_HEIGHT)-1:0] seq_l2_pixel_y;
    logic seq_l2_coord_valid;

    pixel_sequencer #(
        .WIDTH(L2_WIDTH),
        .HEIGHT(L2_HEIGHT),
        .ADDR_WIDTH(18)
    ) u_seq_l2 (
        .clk(clk),
        .rst_n(rst_n),
        .start(seq_l2_start),
        .done(seq_l2_done),
        .read_addr(seq_l2_read_addr),
        .read_enable(seq_l2_read_enable),
        .pixel_x(seq_l2_pixel_x),
        .pixel_y(seq_l2_pixel_y),
        .coord_valid(seq_l2_coord_valid)
    );

    // Sequencer control
    assign seq_l0_start = lk_solve_start && (lk_level == 2'b00);
    assign seq_l1_start = lk_solve_start && (lk_level == 2'b01);
    assign seq_l2_start = lk_solve_start && (lk_level == 2'b10);

    /*
    * Frame Warper Instances
    */

    logic warp_l1_start, warp_l1_done;
    logic warp_l2_start, warp_l2_done;

    // Separate warper output signals (per-level)
    logic [PIXEL_WIDTH-1:0] warp_l1_src_pixel, warp_l2_src_pixel;
    logic [16:0] warp_l1_src_addr;
    logic [17:0] warp_l2_src_addr;
    logic warp_l1_src_re, warp_l2_src_re;

    logic signed [FLOW_WIDTH-1:0] warp_l1_flow_u, warp_l1_flow_v;
    logic signed [FLOW_WIDTH-1:0] warp_l2_flow_u, warp_l2_flow_v;
    logic [16:0] warp_l1_flow_addr;
    logic [17:0] warp_l2_flow_addr;
    logic warp_l1_flow_re, warp_l2_flow_re;

    // Muxed signals (shared BRAM interface)
    logic [PIXEL_WIDTH-1:0] warp_src_pixel;
    logic [17:0] warp_src_addr;
    logic warp_src_re;

    logic signed [FLOW_WIDTH-1:0] warp_flow_u, warp_flow_v;
    logic [17:0] warp_flow_addr;
    logic warp_flow_re;

    // L1 warper (warp L1 current using upsampled L0->L1 flow)
    frame_warper #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .FLOW_WIDTH(FLOW_WIDTH),
        .WIDTH(L1_WIDTH),
        .HEIGHT(L1_HEIGHT),
        .ADDR_WIDTH(17)
    ) u_warp_l1 (
        .clk(clk),
        .rst_n(rst_n),
        .start(warp_l1_start),
        .done(warp_l1_done),
        .src_pixel_data(warp_l1_src_pixel),
        .src_addr(warp_l1_src_addr),
        .src_re(warp_l1_src_re),
        .flow_u_data(warp_l1_flow_u),
        .flow_v_data(warp_l1_flow_v),
        .flow_addr(warp_l1_flow_addr),
        .flow_re(warp_l1_flow_re),
        .warped_pixel_data(l1_warped_write_data),
        .warped_addr(l1_warped_write_addr),
        .warped_we(l1_warped_we)
    );

    // L2 warper (warp L2 current using upsampled L1->L2 flow)
    frame_warper #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .FLOW_WIDTH(FLOW_WIDTH),
        .WIDTH(L2_WIDTH),
        .HEIGHT(L2_HEIGHT),
        .ADDR_WIDTH(18)
    ) u_warp_l2 (
        .clk(clk),
        .rst_n(rst_n),
        .start(warp_l2_start),
        .done(warp_l2_done),
        .src_pixel_data(warp_l2_src_pixel),
        .src_addr(warp_l2_src_addr),
        .src_re(warp_l2_src_re),
        .flow_u_data(warp_l2_flow_u),
        .flow_v_data(warp_l2_flow_v),
        .flow_addr(warp_l2_flow_addr),
        .flow_re(warp_l2_flow_re),
        .warped_pixel_data(l2_warped_write_data),
        .warped_addr(l2_warped_write_addr),
        .warped_we(l2_warped_we)
    );

    // Warper control
    assign warp_l1_start = warp_start && (warp_level == 2'b00);
    assign warp_l2_start = warp_start && (warp_level == 2'b01);
    assign warp_done = (warp_level == 2'b00) ? warp_l1_done : warp_l2_done;

    // Mux warper source pixel data (reads from frame memories)
    always_comb begin
        if (warp_level == 2'b00) begin
            // L1 warper active
            warp_l1_src_pixel = l1_curr_read_data;
            warp_l2_src_pixel = '0;
            warp_src_addr = {1'b0, warp_l1_src_addr};  // Zero-extend to 18 bits
            warp_src_re = warp_l1_src_re;
        end else begin
            // L2 warper active
            warp_l1_src_pixel = '0;
            warp_l2_src_pixel = l2_curr_read_data;
            warp_src_addr = warp_l2_src_addr;
            warp_src_re = warp_l2_src_re;
        end
    end

    // Mux warper flow read requests (reads from flow memories)
    always_comb begin
        if (warp_level == 2'b00) begin
            // L1 warper active
            warp_flow_addr = {1'b0, warp_l1_flow_addr};  // Zero-extend to 18 bits
            warp_flow_re   = warp_l1_flow_re;
            warp_l1_flow_u = warp_flow_u;
            warp_l1_flow_v = warp_flow_v;
            warp_l2_flow_u = '0;
            warp_l2_flow_v = '0;
        end else begin
            // L2 warper active
            warp_flow_addr = warp_l2_flow_addr;
            warp_flow_re   = warp_l2_flow_re;
            warp_l1_flow_u = '0;
            warp_l1_flow_v = '0;
            warp_l2_flow_u = warp_flow_u;
            warp_l2_flow_v = warp_flow_v;
        end
    end

    /*
    * Flow Accumulator Instances
    */

    logic accum_l1_start, accum_l1_done;
    logic accum_l2_start, accum_l2_done;

    // Accumulator read request outputs
    logic [16:0] l1_flow_addr_read_accum;
    logic l1_flow_re_accum;
    logic [17:0] l2_flow_addr_read_accum;
    logic l2_flow_re_accum;

    // L1 accumulator (base=upsampled L0, residual=L1 solver output)
    flow_accumulator #(
        .FLOW_WIDTH(FLOW_WIDTH),
        .WIDTH(L1_WIDTH),
        .HEIGHT(L1_HEIGHT),
        .ADDR_WIDTH(17)
    ) u_accum_l1 (
        .clk(clk),
        .rst_n(rst_n),
        .start(accum_l1_start),
        .done(accum_l1_done),
        // Base flow (upsampled L0, read from L1 flow memory port B)
        .base_flow_u_data(l1_flow_u_read),
        .base_flow_v_data(l1_flow_v_read),
        .base_flow_addr(l1_flow_addr_read_accum),
        .base_flow_re(l1_flow_re_accum),
        // Accumulated flow (write to port A through arbitration MUX)
        .accum_flow_u_data(l1_flow_u_write_accum),
        .accum_flow_v_data(l1_flow_v_write_accum),
        .accum_flow_addr(l1_flow_addr_write_accum),
        .accum_flow_we(l1_flow_we_accum),
        // Residual flow (L1 solver output, read from residual memory)
        .residual_flow_u_data(l1_residual_u_read),
        .residual_flow_v_data(l1_residual_v_read),
        .residual_flow_addr(l1_residual_addr_read),
        .residual_flow_re(l1_residual_re)
    );

    // L2 accumulator (base=upsampled L1, residual=L2 solver output)
    flow_accumulator #(
        .FLOW_WIDTH(FLOW_WIDTH),
        .WIDTH(L2_WIDTH),
        .HEIGHT(L2_HEIGHT),
        .ADDR_WIDTH(18)
    ) u_accum_l2 (
        .clk(clk),
        .rst_n(rst_n),
        .start(accum_l2_start),
        .done(accum_l2_done),
        // Base flow (upsampled L1, read from L2 flow memory port B)
        .base_flow_u_data(l2_flow_u_read),
        .base_flow_v_data(l2_flow_v_read),
        .base_flow_addr(l2_flow_addr_read_accum),
        .base_flow_re(l2_flow_re_accum),
        // Accumulated flow (write to port A through arbitration MUX)
        .accum_flow_u_data(l2_flow_u_write_accum),
        .accum_flow_v_data(l2_flow_v_write_accum),
        .accum_flow_addr(l2_flow_addr_write_accum),
        .accum_flow_we(l2_flow_we_accum),
        // Residual flow (L2 solver output, read from residual memory)
        .residual_flow_u_data(l2_residual_u_read),
        .residual_flow_v_data(l2_residual_v_read),
        .residual_flow_addr(l2_residual_addr_read),
        .residual_flow_re(l2_residual_re)
    );

    // Accumulator control
    assign accum_l1_start = accum_start && (accum_level == 2'b00);
    assign accum_l2_start = accum_start && (accum_level == 2'b01);
    assign accum_done = (accum_level == 2'b00) ? accum_l1_done : accum_l2_done;

    /*
    * Pixel Data Routing (Feed L-K Solver Pipelines)
    */

    logic [PIXEL_WIDTH-1:0] lk_pixel_curr, lk_pixel_prev;
    logic lk_pixel_valid;

    /*
    * Lucas-Kanade Solver Pipelines (One Per Level)
    */

    // Level 0 solver (80x60)
    logic signed [GRAD_WIDTH-1:0] grad_x_l0, grad_y_l0, grad_t_l0;
    logic grad_valid_l0;
    logic signed [ACCUM_WIDTH-1:0] sum_IxIx_l0, sum_IyIy_l0, sum_IxIy_l0;
    logic signed [ACCUM_WIDTH-1:0] sum_IxIt_l0, sum_IyIt_l0;
    logic accum_valid_l0;
    logic signed [FLOW_WIDTH-1:0] lk_flow_u_l0, lk_flow_v_l0;
    logic lk_flow_valid_l0;

    gradient_compute #(
        .WIDTH      (L0_WIDTH),
        .HEIGHT     (L0_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .GRAD_WIDTH (GRAD_WIDTH)
    ) u_gradient_compute_l0 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_curr(lk_pixel_curr),
        .pixel_prev(lk_pixel_prev),
        .pixel_valid(lk_pixel_valid && (lk_level == 2'b00)),
        .pixel_x_in('0),
        .pixel_y_in('0),
        .pixel_x_out(  /* unused */),
        .pixel_y_out(  /* unused */),
        .grad_x(grad_x_l0),
        .grad_y(grad_y_l0),
        .grad_t(grad_t_l0),
        .grad_valid(grad_valid_l0)
    );

    window_accumulator #(
        .WIDTH      (L0_WIDTH),
        .HEIGHT     (L0_HEIGHT),
        .GRAD_WIDTH (GRAD_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) u_window_accumulator_l0 (
        .clk(clk),
        .rst_n(rst_n),
        .grad_x(grad_x_l0),
        .grad_y(grad_y_l0),
        .grad_t(grad_t_l0),
        .grad_valid(grad_valid_l0),
        .accum_x_coord(  /* unused */),
        .accum_y_coord(  /* unused */),
        .sum_IxIx(sum_IxIx_l0),
        .sum_IyIy(sum_IyIy_l0),
        .sum_IxIy(sum_IxIy_l0),
        .sum_IxIt(sum_IxIt_l0),
        .sum_IyIt(sum_IyIt_l0),
        .accum_valid(accum_valid_l0)
    );

    flow_solver #(
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .FLOW_WIDTH (FLOW_WIDTH),
        .FRAC_BITS  (7)
    ) u_flow_solver_l0 (
        .clk(clk),
        .rst_n(rst_n),
        .sum_IxIx(sum_IxIx_l0),
        .sum_IyIy(sum_IyIy_l0),
        .sum_IxIy(sum_IxIy_l0),
        .sum_IxIt(sum_IxIt_l0),
        .sum_IyIt(sum_IyIt_l0),
        .accum_valid(accum_valid_l0),
        .pixel_x_in('0),
        .pixel_y_in('0),
        .pixel_x_out(  /* unused */),
        .pixel_y_out(  /* unused */),
        .flow_u(lk_flow_u_l0),
        .flow_v(lk_flow_v_l0),
        .flow_valid(lk_flow_valid_l0)
    );

    // Level 1 solver (160x120)
    logic signed [GRAD_WIDTH-1:0] grad_x_l1, grad_y_l1, grad_t_l1;
    logic grad_valid_l1;
    logic signed [ACCUM_WIDTH-1:0] sum_IxIx_l1, sum_IyIy_l1, sum_IxIy_l1;
    logic signed [ACCUM_WIDTH-1:0] sum_IxIt_l1, sum_IyIt_l1;
    logic accum_valid_l1;
    logic signed [FLOW_WIDTH-1:0] lk_flow_u_l1, lk_flow_v_l1;
    logic lk_flow_valid_l1;

    gradient_compute #(
        .WIDTH      (L1_WIDTH),
        .HEIGHT     (L1_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .GRAD_WIDTH (GRAD_WIDTH)
    ) u_gradient_compute_l1 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_curr(lk_pixel_curr),
        .pixel_prev(lk_pixel_prev),
        .pixel_valid(lk_pixel_valid && (lk_level == 2'b01)),
        .pixel_x_in('0),
        .pixel_y_in('0),
        .pixel_x_out(  /* unused */),
        .pixel_y_out(  /* unused */),
        .grad_x(grad_x_l1),
        .grad_y(grad_y_l1),
        .grad_t(grad_t_l1),
        .grad_valid(grad_valid_l1)
    );

    window_accumulator #(
        .WIDTH      (L1_WIDTH),
        .HEIGHT     (L1_HEIGHT),
        .GRAD_WIDTH (GRAD_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) u_window_accumulator_l1 (
        .clk(clk),
        .rst_n(rst_n),
        .grad_x(grad_x_l1),
        .grad_y(grad_y_l1),
        .grad_t(grad_t_l1),
        .grad_valid(grad_valid_l1),
        .accum_x_coord(  /* unused */),
        .accum_y_coord(  /* unused */),
        .sum_IxIx(sum_IxIx_l1),
        .sum_IyIy(sum_IyIy_l1),
        .sum_IxIy(sum_IxIy_l1),
        .sum_IxIt(sum_IxIt_l1),
        .sum_IyIt(sum_IyIt_l1),
        .accum_valid(accum_valid_l1)
    );

    flow_solver #(
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .FLOW_WIDTH (FLOW_WIDTH),
        .FRAC_BITS  (7)
    ) u_flow_solver_l1 (
        .clk(clk),
        .rst_n(rst_n),
        .sum_IxIx(sum_IxIx_l1),
        .sum_IyIy(sum_IyIy_l1),
        .sum_IxIy(sum_IxIy_l1),
        .sum_IxIt(sum_IxIt_l1),
        .sum_IyIt(sum_IyIt_l1),
        .accum_valid(accum_valid_l1),
        .pixel_x_in('0),
        .pixel_y_in('0),
        .pixel_x_out(  /* unused */),
        .pixel_y_out(  /* unused */),
        .flow_u(lk_flow_u_l1),
        .flow_v(lk_flow_v_l1),
        .flow_valid(lk_flow_valid_l1)
    );

    // Level 2 solver (320x240)
    logic signed [GRAD_WIDTH-1:0] grad_x_l2, grad_y_l2, grad_t_l2;
    logic grad_valid_l2;
    logic signed [ACCUM_WIDTH-1:0] sum_IxIx_l2, sum_IyIy_l2, sum_IxIy_l2;
    logic signed [ACCUM_WIDTH-1:0] sum_IxIt_l2, sum_IyIt_l2;
    logic accum_valid_l2;
    logic signed [FLOW_WIDTH-1:0] lk_flow_u_l2, lk_flow_v_l2;
    logic lk_flow_valid_l2;

    gradient_compute #(
        .WIDTH      (L2_WIDTH),
        .HEIGHT     (L2_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .GRAD_WIDTH (GRAD_WIDTH)
    ) u_gradient_compute_l2 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_curr(lk_pixel_curr),
        .pixel_prev(lk_pixel_prev),
        .pixel_valid(lk_pixel_valid && (lk_level == 2'b10)),
        .pixel_x_in('0),
        .pixel_y_in('0),
        .pixel_x_out(  /* unused */),
        .pixel_y_out(  /* unused */),
        .grad_x(grad_x_l2),
        .grad_y(grad_y_l2),
        .grad_t(grad_t_l2),
        .grad_valid(grad_valid_l2)
    );

    window_accumulator #(
        .WIDTH      (L2_WIDTH),
        .HEIGHT     (L2_HEIGHT),
        .GRAD_WIDTH (GRAD_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) u_window_accumulator_l2 (
        .clk(clk),
        .rst_n(rst_n),
        .grad_x(grad_x_l2),
        .grad_y(grad_y_l2),
        .grad_t(grad_t_l2),
        .grad_valid(grad_valid_l2),
        .accum_x_coord(  /* unused */),
        .accum_y_coord(  /* unused */),
        .sum_IxIx(sum_IxIx_l2),
        .sum_IyIy(sum_IyIy_l2),
        .sum_IxIy(sum_IxIy_l2),
        .sum_IxIt(sum_IxIt_l2),
        .sum_IyIt(sum_IyIt_l2),
        .accum_valid(accum_valid_l2)
    );

    flow_solver #(
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .FLOW_WIDTH (FLOW_WIDTH),
        .FRAC_BITS  (7)
    ) u_flow_solver_l2 (
        .clk(clk),
        .rst_n(rst_n),
        .sum_IxIx(sum_IxIx_l2),
        .sum_IyIy(sum_IyIy_l2),
        .sum_IxIy(sum_IxIy_l2),
        .sum_IxIt(sum_IxIt_l2),
        .sum_IyIt(sum_IyIt_l2),
        .accum_valid(accum_valid_l2),
        .pixel_x_in('0),
        .pixel_y_in('0),
        .pixel_x_out(  /* unused */),
        .pixel_y_out(  /* unused */),
        .flow_u(lk_flow_u_l2),
        .flow_v(lk_flow_v_l2),
        .flow_valid(lk_flow_valid_l2)
    );

    // MUX solver outputs based on active level
    logic signed [FLOW_WIDTH-1:0] lk_flow_u, lk_flow_v;
    logic lk_flow_valid;

    always_comb begin
        case (lk_level)
            2'b00: begin
                lk_flow_u = lk_flow_u_l0;
                lk_flow_v = lk_flow_v_l0;
                lk_flow_valid = lk_flow_valid_l0;
            end
            2'b01: begin
                lk_flow_u = lk_flow_u_l1;
                lk_flow_v = lk_flow_v_l1;
                lk_flow_valid = lk_flow_valid_l1;
            end
            2'b10: begin
                lk_flow_u = lk_flow_u_l2;
                lk_flow_v = lk_flow_v_l2;
                lk_flow_valid = lk_flow_valid_l2;
            end
            default: begin
                lk_flow_u = '0;
                lk_flow_v = '0;
                lk_flow_valid = 1'b0;
            end
        endcase
    end

    // Final outputs (only from L2 for now)
    assign flow_u     = lk_flow_u;
    assign flow_v     = lk_flow_v;
    assign flow_valid = lk_flow_valid;

    /*
    * Flow Write Path (L-K Solver -> Flow/Residual Memory)
    */

    // Flow write coordinates and control
    logic [$clog2(L2_WIDTH)-1:0] flow_write_x;
    logic [$clog2(L2_HEIGHT)-1:0] flow_write_y;
    logic flow_write_coord_valid;

    // Select coordinate source based on active level
    always_comb begin
        case (lk_level)
            2'b00: begin
                flow_write_x = seq_l0_pixel_x;
                flow_write_y = seq_l0_pixel_y;
                flow_write_coord_valid = seq_l0_coord_valid;
            end
            2'b01: begin
                flow_write_x = seq_l1_pixel_x;
                flow_write_y = seq_l1_pixel_y;
                flow_write_coord_valid = seq_l1_coord_valid;
            end
            2'b10: begin
                flow_write_x = seq_l2_pixel_x;
                flow_write_y = seq_l2_pixel_y;
                flow_write_coord_valid = seq_l2_coord_valid;
            end
            default: begin
                flow_write_x = '0;
                flow_write_y = '0;
                flow_write_coord_valid = 1'b0;
            end
        endcase
    end

    // Route solver output to appropriate memory
    always_comb begin
        // Default: no writes
        l0_flow_we = 1'b0;
        l0_flow_addr_write = '0;
        l0_flow_u_write = '0;
        l0_flow_v_write = '0;

        l1_residual_we = 1'b0;
        l1_residual_addr_write = '0;
        l1_residual_u_write = '0;
        l1_residual_v_write = '0;

        l2_residual_we = 1'b0;
        l2_residual_addr_write = '0;
        l2_residual_u_write = '0;
        l2_residual_v_write = '0;

        if (lk_flow_valid && flow_write_coord_valid) begin
            case (lk_level)
                2'b00: begin
                    // L0: Write directly to flow memory (no accumulation needed)
                    l0_flow_addr_write = flow_write_y * L0_WIDTH + flow_write_x;
                    l0_flow_u_write = lk_flow_u;
                    l0_flow_v_write = lk_flow_v;
                    l0_flow_we = 1'b1;
                end

                2'b01: begin
                    // L1: Write to residual memory (will be accumulated later)
                    l1_residual_addr_write = flow_write_y * L1_WIDTH + flow_write_x;
                    l1_residual_u_write = lk_flow_u;
                    l1_residual_v_write = lk_flow_v;
                    l1_residual_we = 1'b1;
                end

                2'b10: begin
                    // L2: Write to residual memory (will be accumulated later)
                    l2_residual_addr_write = flow_write_y * L2_WIDTH + flow_write_x;
                    l2_residual_u_write = lk_flow_u;
                    l2_residual_v_write = lk_flow_v;
                    l2_residual_we = 1'b1;
                end

                default: begin
                    l1_residual_addr_write = 0;
                    l1_residual_u_write = 0;
                    l1_residual_v_write = 0;
                    l1_residual_we = 1'b0;
                end
            endcase
        end
    end

    /*
    * BRAM Read Port Routing (State-Aware Arbitration)
    */

    always_comb begin
        // Default: all read enables off
        l0_read_enable      = 1'b0;
        l1_read_enable      = 1'b0;
        l2_read_enable      = 1'b0;
        l0_warped_re        = 1'b0;
        l1_warped_re        = 1'b0;
        l2_warped_re        = 1'b0;

        // Default addresses
        l0_read_addr        = '0;
        l1_read_addr        = '0;
        l2_read_addr        = '0;
        l0_warped_read_addr = '0;
        l1_warped_read_addr = '0;
        l2_warped_read_addr = '0;

        case (fsm_state)
            4'd3: begin  // SOLVE_L0 (original frames, no warping needed)
                l0_read_addr   = seq_l0_read_addr;
                l0_read_enable = seq_l0_read_enable;
            end

            4'd5: begin  // SOLVE_L1 (uses warped current vs original previous)
                // Previous frame: original L1
                l1_read_addr = seq_l1_read_addr;
                l1_read_enable = seq_l1_read_enable;

                // Current frame: warped L1
                l1_warped_read_addr = seq_l1_read_addr;
                l1_warped_re = seq_l1_read_enable;
            end

            4'd9: begin  // SOLVE_L2 (uses warped current vs original previous)
                // Previous frame: original L2
                l2_read_addr = seq_l2_read_addr;
                l2_read_enable = seq_l2_read_enable;

                // Current frame: warped L2
                l2_warped_read_addr = seq_l2_read_addr;
                l2_warped_re = seq_l2_read_enable;
            end

            4'd4: begin  // WARP_L1 (warper reads L1 current frame)
                l1_read_addr   = warp_src_addr[16:0];
                l1_read_enable = warp_src_re;
            end

            4'd8: begin  // WARP_L2 (warper reads L2 current frame)
                l2_read_addr   = warp_src_addr;
                l2_read_enable = warp_src_re;
            end

            default: begin
                // Other states (UPSAMPLE, ACCUM) don't need frame memory reads
            end
        endcase
    end

    /*
    * Pixel Data MUX (Route Frames to Active L-K Solver)
    */

    always_comb begin
        case (lk_level)
            2'b00: begin  // L0 solver: original frames (no warping at coarsest level)
                lk_pixel_curr  = l0_curr_read_data;
                lk_pixel_prev  = l0_prev_read_data;
                lk_pixel_valid = seq_l0_coord_valid;
            end

            2'b01: begin  // L1 solver: warped current vs original previous
                lk_pixel_curr  = l1_warped_read_data;
                lk_pixel_prev  = l1_prev_read_data;
                lk_pixel_valid = seq_l1_coord_valid;
            end

            2'b10: begin  // L2 solver: warped current vs original previous
                lk_pixel_curr  = l2_warped_read_data;
                lk_pixel_prev  = l2_prev_read_data;
                lk_pixel_valid = seq_l2_coord_valid;
            end

            default: begin
                lk_pixel_curr  = '0;
                lk_pixel_prev  = '0;
                lk_pixel_valid = 1'b0;
            end
        endcase
    end

    /*
    * Flow Memory Read Port Arbitration
    *
    * Arbitrates flow memory port B among three requestors:
    *   - Upsampler: Reads coarse flow during UPSAMPLE states
    *   - Warper: Reads flow during WARP states
    *   - Accumulator: Reads base flow during ACCUM states
    * FSM ensures mutual exclusivity.
    */

    always_comb begin
        // L0 Flow Memory Port B Arbitration (Only Upsampler Reads L0)
        if (upsample_start && upsample_level == 2'b00) begin
            // UPSAMPLE_L0: Route upsampler signals to L0 flow memory port B
            l0_flow_addr_read = l0_flow_addr_read_upsample;
            l0_flow_re = l0_flow_re_upsample;
        end else begin
            // Default: No access
            l0_flow_addr_read = '0;
            l0_flow_re = 1'b0;
        end

        // L1 Flow Memory Port B Arbitration (Upsampler, Warper, Accumulator)
        if (upsample_start && upsample_level == 2'b01) begin
            // UPSAMPLE_L1: Route upsampler signals to L1 flow memory port B
            l1_flow_addr_read = l1_flow_addr_read_upsample;
            l1_flow_re = l1_flow_re_upsample;
        end else if (warp_start && warp_level == 2'b00) begin
            // WARP_L1: Route warper signals to L1 flow memory port B
            l1_flow_addr_read = warp_flow_addr[16:0];
            l1_flow_re = warp_flow_re;
        end else if (accum_start && accum_level == 2'b00) begin
            // ACCUM_L1: Route accumulator signals to L1 flow memory port B
            l1_flow_addr_read = l1_flow_addr_read_accum;
            l1_flow_re = l1_flow_re_accum;
        end else begin
            // Default: No access
            l1_flow_addr_read = '0;
            l1_flow_re = 1'b0;
        end

        // L2 Flow Memory Port B Arbitration (Warper, Accumulator)
        if (warp_start && warp_level == 2'b01) begin
            // WARP_L2: Route warper signals to L2 flow memory port B
            l2_flow_addr_read = warp_flow_addr;
            l2_flow_re = warp_flow_re;
        end else if (accum_start && accum_level == 2'b01) begin
            // ACCUM_L2: Route accumulator signals to L2 flow memory port B
            l2_flow_addr_read = l2_flow_addr_read_accum;
            l2_flow_re = l2_flow_re_accum;
        end else begin
            // Default: No access
            l2_flow_addr_read = '0;
            l2_flow_re = 1'b0;
        end
    end

    // Route flow data from memories to shared warper interface
    assign warp_flow_u = (warp_level == 2'b00) ? l1_flow_u_read : l2_flow_u_read;
    assign warp_flow_v = (warp_level == 2'b00) ? l1_flow_v_read : l2_flow_v_read;

endmodule : optical_flow_top_pyramidal
