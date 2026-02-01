/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/gradient_compute.sv
 *
 * Description: Computes spatial (Ix, Iy) and temporal (It) gradients.
 *              - Sobel operators for Ix/Iy (3x3 convolution)
 *              - Simple frame difference for It
 *              Unoptimized version: combinational Sobel with no pipelining.
 */

`timescale 1ns / 1ps

module gradient_compute #(
    parameter int PIXEL_WIDTH = 8,
    parameter int GRAD_WIDTH  = 12  // S12 signed gradient
) (
    input logic clk,
    input logic rst_n,

    input logic [PIXEL_WIDTH-1:0] pixel_curr,  // Current frame pixel
    input logic [PIXEL_WIDTH-1:0] pixel_prev,  // Previous frame pixel
    input logic                   pixel_valid,

    output logic signed [GRAD_WIDTH-1:0] grad_x,     // Spatial gradient X (Ix)
    output logic signed [GRAD_WIDTH-1:0] grad_y,     // Spatial gradient Y (Iy)
    output logic signed [GRAD_WIDTH-1:0] grad_t,     // Temporal gradient (It)
    output logic                         grad_valid
);

    /*
     * 3x3 Line Buffer for Spatial Gradients
     * Note: Sobel only needs 3x3 window, but this computes on averaged frame.
     */
    logic [PIXEL_WIDTH-1:0] window_curr[2][2];
    logic [PIXEL_WIDTH-1:0] window_prev[2][2];
    logic window_valid;

    // Instantiate 3x3 line buffers (extracts from 5x5)
    logic [PIXEL_WIDTH-1:0] window_curr_5x5[4][4];
    logic [PIXEL_WIDTH-1:0] window_prev_5x5[4][4];

    line_buffer_5x5 #(
        .WIDTH(320),  // TODO: Parameterize from top
        .HEIGHT(240),
        .DATA_WIDTH(PIXEL_WIDTH)
    ) u_linebuf_curr (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(pixel_curr),
        .data_valid(pixel_valid),
        .window(window_curr_5x5),
        .window_valid(window_valid)
    );

    line_buffer_5x5 #(
        .WIDTH(320),
        .HEIGHT(240),
        .DATA_WIDTH(PIXEL_WIDTH)
    ) u_linebuf_prev (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(pixel_prev),
        .data_valid(pixel_valid),
        .window(window_prev_5x5),
        .window_valid(  /* unused */)
    );

    // Extract center 3x3 from 5x5 windows
    always_comb begin
        for (int i = 0; i < 3; i++) begin
            for (int j = 0; j < 3; j++) begin
                window_curr[i][j] = window_curr_5x5[i+1][j+1];
                window_prev[i][j] = window_prev_5x5[i+1][j+1];
            end
        end
    end

    /*
     * Sobel Operator (Combinational - long path)
     * Sobel X:  [-1  0  1]     Sobel Y:  [-1 -2 -1]
     *           [-2  0  2]               [ 0  0  0]
     *           [-1  0  1] / 8           [ 1  2  1] / 8
     */
    logic signed [GRAD_WIDTH-1:0] sobel_x_comb, sobel_y_comb;
    logic signed [GRAD_WIDTH-1:0] temporal_comb;

    always_comb begin
        // Average the two frames for spatial gradients (reduces noise)
        logic signed [PIXEL_WIDTH:0] avg_window[2][2];
        for (int i = 0; i < 3; i++) begin
            for (int j = 0; j < 3; j++) begin
                avg_window[i][j] = (window_curr[i][j] + window_prev[i][j]) >> 1;
            end
        end

        // Sobel X (vertical edges)
        logic signed [GRAD_WIDTH+2:0] sobel_x_accum;
        sobel_x_accum = -$signed({1'b0, avg_window[0][0]}) - 2 * $signed({1'b0, avg_window[1][0]}) -
            $signed({1'b0, avg_window[2][0]}) + $signed({1'b0, avg_window[0][2]}) +
            2 * $signed({1'b0, avg_window[1][2]}) + $signed({1'b0, avg_window[2][2]});
        sobel_x_comb = sobel_x_accum >>> 3;  // Divide by 8

        // Sobel Y (horizontal edges)
        logic signed [GRAD_WIDTH+2:0] sobel_y_accum;
        sobel_y_accum = -$signed({1'b0, avg_window[0][0]}) - 2 * $signed({1'b0, avg_window[0][1]}) -
            $signed({1'b0, avg_window[0][2]}) + $signed({1'b0, avg_window[2][0]}) +
            2 * $signed({1'b0, avg_window[2][1]}) + $signed({1'b0, avg_window[2][2]});
        sobel_y_comb = sobel_y_accum >>> 3;

        // Temporal gradient (center pixel difference)
        temporal_comb = $signed({1'b0, window_prev[1][1]}) - $signed({1'b0, window_curr[1][1]});
    end

    // Register outputs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grad_x     <= '0;
            grad_y     <= '0;
            grad_t     <= '0;
            grad_valid <= 1'b0;
        end else begin
            grad_x     <= sobel_x_comb;
            grad_y     <= sobel_y_comb;
            grad_t     <= temporal_comb;
            grad_valid <= window_valid;
        end
    end

endmodule : gradient_compute
