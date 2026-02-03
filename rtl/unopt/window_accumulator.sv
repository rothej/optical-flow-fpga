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
        .window_valid(window_valid)
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
    * Structure Tensor Accumulation
    *
    * - 5 products computed per window position (25 positions)
    * - All 25 values summed in a linear chain
    * Total: ~125 operations in one combinational path
    */
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

        // Linear accumulation (long adder chain)
        for (int i = 0; i < WINDOW_SIZE; i++) begin
            for (int j = 0; j < WINDOW_SIZE; j++) begin
                // Compute products (unsigned to signed extension)
                logic signed [2*GRAD_WIDTH-1:0] prod_IxIx;
                logic signed [2*GRAD_WIDTH-1:0] prod_IyIy;
                logic signed [2*GRAD_WIDTH-1:0] prod_IxIy;
                logic signed [2*GRAD_WIDTH-1:0] prod_IxIt;
                logic signed [2*GRAD_WIDTH-1:0] prod_IyIt;

                // Explicit signed multiplication (for synth)
                prod_IxIx  = $signed(window_Ix[i][j]) * $signed(window_Ix[i][j]);
                prod_IyIy  = $signed(window_Iy[i][j]) * $signed(window_Iy[i][j]);
                prod_IxIy  = $signed(window_Ix[i][j]) * $signed(window_Iy[i][j]);
                prod_IxIt  = $signed(window_Ix[i][j]) * $signed(window_It[i][j]);
                prod_IyIt  = $signed(window_Iy[i][j]) * $signed(window_It[i][j]);

                // Accumulate (linear chain)
                accum_IxIx = accum_IxIx + prod_IxIx;
                accum_IyIy = accum_IyIy + prod_IyIy;
                accum_IxIy = accum_IxIy + prod_IxIy;
                accum_IxIt = accum_IxIt + prod_IxIt;
                accum_IyIt = accum_IyIt + prod_IyIt;
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
        end else begin
            sum_IxIx    <= accum_IxIx;
            sum_IyIy    <= accum_IyIy;
            sum_IxIy    <= accum_IxIy;
            sum_IxIt    <= accum_IxIt;
            sum_IyIt    <= accum_IyIt;
            accum_valid <= window_valid;
        end
    end

endmodule : window_accumulator
