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
 *              - Temporal gradient: It = I_prev - I_curr
 *              - Simple frame difference for It
 *              Unoptimized version: combinational Sobel with no pipelining.
 */

`timescale 1ns / 1ps

module gradient_compute #(
    parameter int WIDTH       = 320,
    parameter int HEIGHT      = 240,
    parameter int PIXEL_WIDTH = 8,
    parameter int GRAD_WIDTH  = 12    // S12 signed gradient
) (
    input logic clk,
    input logic rst_n,

    input logic [PIXEL_WIDTH-1:0] pixel_curr,  // Current frame pixel
    input logic [PIXEL_WIDTH-1:0] pixel_prev,  // Previous frame pixel
    input logic                   pixel_valid,

    input  logic [9:0] pixel_x_in,
    input  logic [8:0] pixel_y_in,
    output logic [9:0] pixel_x_out,
    output logic [8:0] pixel_y_out,

    output logic signed [GRAD_WIDTH-1:0] grad_x,     // Spatial gradient X (Ix)
    output logic signed [GRAD_WIDTH-1:0] grad_y,     // Spatial gradient Y (Iy)
    output logic signed [GRAD_WIDTH-1:0] grad_t,     // Temporal gradient (It)
    output logic                         grad_valid
);

    /*
     * 3x3 Line Buffer for Spatial Gradients
     * Note: Sobel only needs 3x3 window, but this computes on averaged frame.
     */
    logic signed [PIXEL_WIDTH-1:0] window_curr[3][3];
    logic signed [PIXEL_WIDTH-1:0] window_prev[3][3];
    logic window_valid;

    // Instantiate 3x3 line buffers (extracts from 5x5)
    logic signed [PIXEL_WIDTH-1:0] window_curr_5x5[5][5];
    logic signed [PIXEL_WIDTH-1:0] window_prev_5x5[5][5];

    // Coordinate outputs
    logic [$clog2(WIDTH)-1:0] window_x_curr, window_x_prev;
    logic [$clog2(HEIGHT)-1:0] window_y_curr, window_y_prev;

    line_buffer_5x5 #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .DATA_WIDTH(PIXEL_WIDTH)
    ) u_linebuf_curr (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(pixel_curr),
        .data_valid(pixel_valid),
        .window(window_curr_5x5),
        .window_valid(window_valid),
        .window_x(window_x_curr),
        .window_y(window_y_curr)
    );

    line_buffer_5x5 #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .DATA_WIDTH(PIXEL_WIDTH)
    ) u_linebuf_prev (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(pixel_prev),
        .data_valid(pixel_valid),
        .window(window_prev_5x5),
        .window_valid(  /* unused */),
        .window_x(window_x_prev),
        .window_y(window_y_prev)
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
     * Sobel Operator with Clearer Structure
     *
     * Note: Sobel uses small constant weights (1, 2) that won't infer DSPs,
     *       but separating multiply from accumulation helps synthesis.
     */
    logic signed [GRAD_WIDTH-1:0] sobel_x_comb, sobel_y_comb;
    logic signed [GRAD_WIDTH-1:0] temporal_comb;

    always_comb begin
        logic signed [PIXEL_WIDTH:0] avg_window[3][3];
        logic signed [GRAD_WIDTH+2:0] sobel_x_left, sobel_x_right;
        logic signed [GRAD_WIDTH+2:0] sobel_y_top, sobel_y_bottom;

        // Average the two frames for spatial gradients (reduces noise)
        for (int i = 0; i < 3; i++) begin
            for (int j = 0; j < 3; j++) begin
                avg_window[i][j] = (window_curr[i][j] + window_prev[i][j]) >> 1;
            end
        end

        // Sobel X: Separate left and right columns for clarity
        sobel_x_left = -$signed({1'b0, avg_window[0][0]}) -
            ($signed({1'b0, avg_window[1][0]}) <<< 1) - $signed({1'b0, avg_window[2][0]});

        sobel_x_right = $signed({1'b0, avg_window[0][2]}) +
            ($signed({1'b0, avg_window[1][2]}) <<< 1) + $signed({1'b0, avg_window[2][2]});

        sobel_x_comb = (sobel_x_left + sobel_x_right) >>> 3;  // Divide by 8

        // Sobel Y: Separate top and bottom rows
        sobel_y_top = -$signed({1'b0, avg_window[0][0]}) -
            ($signed({1'b0, avg_window[0][1]}) <<< 1) - $signed({1'b0, avg_window[0][2]});

        sobel_y_bottom = $signed({1'b0, avg_window[2][0]}) +
            ($signed({1'b0, avg_window[2][1]}) <<< 1) + $signed({1'b0, avg_window[2][2]});

        sobel_y_comb = (sobel_y_top + sobel_y_bottom) >>> 3;

        // Temporal gradient
        temporal_comb = $signed({4'b0, window_prev[1][1]}) - $signed({4'b0, window_curr[1][1]});
    end

    // Register outputs
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grad_x      <= '0;
            grad_y      <= '0;
            grad_t      <= '0;
            grad_valid  <= 1'b0;
            pixel_x_out <= '0;
            pixel_y_out <= '0;
        end else begin
            grad_x      <= sobel_x_comb;
            grad_y      <= sobel_y_comb;
            grad_t      <= temporal_comb;
            grad_valid  <= window_valid;
            pixel_x_out <= {1'b0, window_x_curr};
            pixel_y_out <= {1'b0, window_y_curr};
        end
    end

endmodule : gradient_compute
