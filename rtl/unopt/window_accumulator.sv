/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/window_accumulator.sv
 *
 * Description: Accumulates 5x5 windows of gradient products with no pipelining.
 *              Critical path has qty 5 12-bit multiplications (Ix*Ix thru Iy*It) and qty 25
 *              parallel accumulations all done on a single clock cycle. Should fail timing at
 *              reasonable clock frequencies.
 */

`timescale 1ns / 1ps

module window_accumulator #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240,
    parameter int GRAD_WIDTH = 12,  // Gradient bit width (signed)
    parameter int WINDOW_SIZE = 5,
    parameter int ACCUM_WIDTH = 32  // Accumulator width
) (
    input logic clk,
    input logic rst_n,

    input logic signed [GRAD_WIDTH-1:0] grad_x,
    input logic signed [GRAD_WIDTH-1:0] grad_y,
    input logic signed [GRAD_WIDTH-1:0] grad_t,
    input logic                         grad_valid,

    output logic        [            9:0] accum_x_coord,
    output logic        [            8:0] accum_y_coord,
    output logic signed [ACCUM_WIDTH-1:0] sum_IxIx,
    output logic signed [ACCUM_WIDTH-1:0] sum_IyIy,
    output logic signed [ACCUM_WIDTH-1:0] sum_IxIy,
    output logic signed [ACCUM_WIDTH-1:0] sum_IxIt,
    output logic signed [ACCUM_WIDTH-1:0] sum_IyIt,
    output logic                          accum_valid
);

    /*
    * 5x5 line buffers for gradient values.
    */
    logic signed [GRAD_WIDTH-1:0] window_Ix[WINDOW_SIZE][WINDOW_SIZE];
    logic signed [GRAD_WIDTH-1:0] window_Iy[WINDOW_SIZE][WINDOW_SIZE];
    logic signed [GRAD_WIDTH-1:0] window_It[WINDOW_SIZE][WINDOW_SIZE];
    logic window_valid;
    logic [$clog2(WIDTH)-1:0] window_x_Ix;
    logic [$clog2(HEIGHT)-1:0] window_y_Ix;

    line_buffer_5x5 #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .DATA_WIDTH(GRAD_WIDTH)
    ) u_linebuf_Ix (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(grad_x),
        .data_valid(grad_valid),
        .window(window_Ix),
        .window_valid(window_valid),
        .window_x(window_x_Ix),
        .window_y(window_y_Ix)
    );

    line_buffer_5x5 #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .DATA_WIDTH(GRAD_WIDTH)
    ) u_linebuf_Iy (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(grad_y),
        .data_valid(grad_valid),
        .window(window_Iy),
        .window_valid(  /* unused */)
    );

    line_buffer_5x5 #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .DATA_WIDTH(GRAD_WIDTH)
    ) u_linebuf_It (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(grad_t),
        .data_valid(grad_valid),
        .window(window_It),
        .window_valid(  /* unused */)
    );

    /*
    * Structure Tensor Accumulation with DSP Inference
    *
    * Stage 1: Compute 5 products per window position (uses DSP48E1 multipliers)
    * Stage 2: Accumulate 25 values
    */

    // Stage 1: Pipelined multiplications (125 products total)
    (* use_dsp = "yes" *) logic signed [2*GRAD_WIDTH-1:0] prod_IxIx_pipe[WINDOW_SIZE][WINDOW_SIZE];
    (* use_dsp = "yes" *) logic signed [2*GRAD_WIDTH-1:0] prod_IyIy_pipe[WINDOW_SIZE][WINDOW_SIZE];
    (* use_dsp = "yes" *) logic signed [2*GRAD_WIDTH-1:0] prod_IxIy_pipe[WINDOW_SIZE][WINDOW_SIZE];
    (* use_dsp = "yes" *) logic signed [2*GRAD_WIDTH-1:0] prod_IxIt_pipe[WINDOW_SIZE][WINDOW_SIZE];
    (* use_dsp = "yes" *) logic signed [2*GRAD_WIDTH-1:0] prod_IyIt_pipe[WINDOW_SIZE][WINDOW_SIZE];

    logic window_valid_d1;
    logic [$clog2(WIDTH)-1:0] window_x_Ix_d1;
    logic [$clog2(HEIGHT)-1:0] window_y_Ix_d1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < WINDOW_SIZE; i++) begin
                for (int j = 0; j < WINDOW_SIZE; j++) begin
                    prod_IxIx_pipe[i][j] <= '0;
                    prod_IyIy_pipe[i][j] <= '0;
                    prod_IxIy_pipe[i][j] <= '0;
                    prod_IxIt_pipe[i][j] <= '0;
                    prod_IyIt_pipe[i][j] <= '0;
                end
            end
            window_valid_d1 <= 1'b0;
            window_x_Ix_d1  <= '0;
            window_y_Ix_d1  <= '0;
        end else begin
            // Pipeline stage 1: Multiply (infers DSP48E1)
            for (int i = 0; i < WINDOW_SIZE; i++) begin
                for (int j = 0; j < WINDOW_SIZE; j++) begin
                    prod_IxIx_pipe[i][j] <= $signed(window_Ix[i][j]) * $signed(window_Ix[i][j]);
                    prod_IyIy_pipe[i][j] <= $signed(window_Iy[i][j]) * $signed(window_Iy[i][j]);
                    prod_IxIy_pipe[i][j] <= $signed(window_Ix[i][j]) * $signed(window_Iy[i][j]);
                    prod_IxIt_pipe[i][j] <= $signed(window_Ix[i][j]) * $signed(window_It[i][j]);
                    prod_IyIt_pipe[i][j] <= $signed(window_Iy[i][j]) * $signed(window_It[i][j]);
                end
            end
            window_valid_d1 <= window_valid;
            window_x_Ix_d1  <= window_x_Ix;
            window_y_Ix_d1  <= window_y_Ix;
        end
    end

    // Stage 2: Combinational accumulation (linear adder chain)
    logic signed [ACCUM_WIDTH-1:0] accum_IxIx;
    logic signed [ACCUM_WIDTH-1:0] accum_IyIy;
    logic signed [ACCUM_WIDTH-1:0] accum_IxIy;
    logic signed [ACCUM_WIDTH-1:0] accum_IxIt;
    logic signed [ACCUM_WIDTH-1:0] accum_IyIt;

    always_comb begin
        accum_IxIx = '0;
        accum_IyIy = '0;
        accum_IxIy = '0;
        accum_IxIt = '0;
        accum_IyIt = '0;

        // Accumulate pipelined products
        for (int i = 0; i < WINDOW_SIZE; i++) begin
            for (int j = 0; j < WINDOW_SIZE; j++) begin
                accum_IxIx = accum_IxIx + prod_IxIx_pipe[i][j];
                accum_IyIy = accum_IyIy + prod_IyIy_pipe[i][j];
                accum_IxIy = accum_IxIy + prod_IxIy_pipe[i][j];
                accum_IxIt = accum_IxIt + prod_IxIt_pipe[i][j];
                accum_IyIt = accum_IyIt + prod_IyIt_pipe[i][j];
            end
        end
    end

    // Register outputs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_IxIx    <= '0;
            sum_IyIy    <= '0;
            sum_IxIy    <= '0;
            sum_IxIt    <= '0;
            sum_IyIt    <= '0;
            accum_valid <= 1'b0;
            accum_x_coord <= '0;
            accum_y_coord <= '0;
        end else begin
            sum_IxIx    <= accum_IxIx;
            sum_IyIy    <= accum_IyIy;
            sum_IxIy    <= accum_IxIy;
            sum_IxIt    <= accum_IxIt;
            sum_IyIt    <= accum_IyIt;
            accum_valid <= window_valid_d1;
            accum_x_coord <= {1'b0, window_x_Ix_d1};
            accum_y_coord <= {1'b0, window_y_Ix_d1};
        end
    end

endmodule : window_accumulator
