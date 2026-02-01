/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/common/line_buffer_5x5.sv
 *
 * Description: Buffers qty 4 complete image rows (lines) plus a 5-element shift reg for the
 *              current row. Provides a 5x5 pixel neighborhood centered on current pixel position.
 *              Essential for spacial operations (convolution, local accumulation) and uses
 *              distributed RAM (FFs) for line storage (needs single-cycle random access).
 *              Not timing critical.
 */


`timescale 1ns / 1ps

module line_buffer_5x5 #(
    parameter int WIDTH = 320,
    parameter int HEIGHT = 240,
    parameter int DATA_WIDTH = 12
) (
    input logic clk,
    input logic rst_n,

    input logic signed [DATA_WIDTH-1:0] data_in,
    input logic                         data_valid,

    output logic signed [DATA_WIDTH-1:0] window      [5][5],
    output logic                         window_valid
);

    // Line buffer storage (4 lines + current row)
    logic signed [DATA_WIDTH-1:0] line0[WIDTH];
    logic signed [DATA_WIDTH-1:0] line1[WIDTH];
    logic signed [DATA_WIDTH-1:0] line2[WIDTH];
    logic signed [DATA_WIDTH-1:0] line3[WIDTH];

    // Shift registers for current line
    logic signed [DATA_WIDTH-1:0] current[5];

    // Position tracking
    logic [$clog2(WIDTH)-1:0] col;
    logic [$clog2(HEIGHT)-1:0] row;

    // Valid signal - window ready after 4 full lines + 4 pixels
    logic valid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col <= '0;
            row <= '0;
            valid_q <= 1'b0;

            for (int i = 0; i < 5; i++) begin
                current[i] <= '0;
            end
        end else if (data_valid) begin
            // Shift current line registers
            current[4] <= current[3];
            current[3] <= current[2];
            current[2] <= current[1];
            current[1] <= current[0];
            current[0] <= data_in;

            // Update column/row counters
            if (col == WIDTH - 1) begin
                col <= '0;
                if (row == HEIGHT - 1) begin
                    row <= '0;
                end else begin
                    row <= row + 1;
                end
            end else begin
                col <= col + 1;
            end

            // Window valid after filling 4 lines + 4 columns
            if (row >= 4 && col >= 4) begin
                valid_q <= 1'b1;
            end else begin
                valid_q <= 1'b0;
            end
        end
    end

    // Line buffer shifts (FIFO-like)
    always_ff @(posedge clk) begin
        if (data_valid) begin
            line3[col] <= line2[col];
            line2[col] <= line1[col];
            line1[col] <= line0[col];
            line0[col] <= current[0];
        end
    end

    // Output window assignment (combinational)
    always_comb begin
        // Row 0 (oldest)
        window[0][0] = line3[col];
        window[0][1] = (col == 0) ? line3[WIDTH-1] : line3[col-1];
        window[0][2] = (col <= 1) ? line3[WIDTH-2+col] : line3[col-2];
        window[0][3] = (col <= 2) ? line3[WIDTH-3+col] : line3[col-3];
        window[0][4] = (col <= 3) ? line3[WIDTH-4+col] : line3[col-4];

        // Row 1
        window[1][0] = line2[col];
        window[1][1] = (col == 0) ? line2[WIDTH-1] : line2[col-1];
        window[1][2] = (col <= 1) ? line2[WIDTH-2+col] : line2[col-2];
        window[1][3] = (col <= 2) ? line2[WIDTH-3+col] : line2[col-3];
        window[1][4] = (col <= 3) ? line2[WIDTH-4+col] : line2[col-4];

        // Row 2
        window[2][0] = line1[col];
        window[2][1] = (col == 0) ? line1[WIDTH-1] : line1[col-1];
        window[2][2] = (col <= 1) ? line1[WIDTH-2+col] : line1[col-2];
        window[2][3] = (col <= 2) ? line1[WIDTH-3+col] : line1[col-3];
        window[2][4] = (col <= 3) ? line1[WIDTH-4+col] : line1[col-4];

        // Row 3
        window[3][0] = line0[col];
        window[3][1] = (col == 0) ? line0[WIDTH-1] : line0[col-1];
        window[3][2] = (col <= 1) ? line0[WIDTH-2+col] : line0[col-2];
        window[3][3] = (col <= 2) ? line0[WIDTH-3+col] : line0[col-3];
        window[3][4] = (col <= 3) ? line0[WIDTH-4+col] : line0[col-4];

        // Row 4 (current)
        window[4][0] = current[0];
        window[4][1] = current[1];
        window[4][2] = current[2];
        window[4][3] = current[3];
        window[4][4] = current[4];
    end

    assign window_valid = valid_q;

endmodule
