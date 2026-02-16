/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/frame_warper.sv
 *
 * Description: Warps a frame using optical flow via bilinear interpolation.
 *              Reads source frame + flow field, writes warped frame to destination BRAM.
 *
 *              Warping equation:
 *                I_warped(x, y) = I_src(x + u(x,y), y + v(x,y))
 *
 *              Unoptimized: Combinational 4-way multiply-accumulate (critical path).
 */

`timescale 1ns / 1ps

module frame_warper #(
    parameter int PIXEL_WIDTH = 8,
    parameter int FLOW_WIDTH  = 16,   // S8.7 fixed-point
    parameter int WIDTH       = 160,
    parameter int HEIGHT      = 120,
    parameter int ADDR_WIDTH  = 17
) (
    input logic clk,
    input logic rst_n,

    // Control
    input  logic start,
    output logic done,

    // Source frame read (BRAM)
    input  logic [PIXEL_WIDTH-1:0] src_pixel_data,
    output logic [ ADDR_WIDTH-1:0] src_addr,
    output logic                   src_re,

    // Flow field read (BRAM)
    input  logic signed [FLOW_WIDTH-1:0] flow_u_data,
    input  logic signed [FLOW_WIDTH-1:0] flow_v_data,
    output logic        [ADDR_WIDTH-1:0] flow_addr,
    output logic                         flow_re,

    // Warped frame write (BRAM)
    output logic [PIXEL_WIDTH-1:0] warped_pixel_data,
    output logic [ ADDR_WIDTH-1:0] warped_addr,
    output logic                   warped_we
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE,
        READ_FLOW,  // Read flow vector for current pixel
        WAIT_FLOW,  // Wait for BRAM latency
        READ_CORNERS,  // Read 4 corner pixels for bilinear interpolation
        WAIT_READ,  // Wait for BRAM latency
        INTERPOLATE,  // Compute bilinear interpolation
        WRITE_PIXEL  // Write warped pixel
    } state_e;

    state_e state;

    // Output pixel counters (raster scan)
    logic [$clog2(WIDTH)-1:0] out_x;
    logic [$clog2(HEIGHT)-1:0] out_y;

    // Warped source coordinates (fixed-point)
    logic signed [FLOW_WIDTH-1:0] src_x_fp, src_y_fp;  // S8.7 format
    logic [$clog2(WIDTH)-1:0] src_x0, src_x1;
    logic [$clog2(HEIGHT)-1:0] src_y0, src_y1;

    // Bilinear interpolation weights (fractional part of coordinates)
    logic [6:0] wx, wy;  // 7-bit fractional (0.0 to 0.9921875 in steps of 1/128)

    // Corner pixel storage (4 samples for bilinear)
    logic [PIXEL_WIDTH-1:0] corners[4];  // [f00, f10, f01, f11]
    logic [1:0] corner_idx;

    // Interpolated result
    logic [PIXEL_WIDTH-1:0] interp_pixel;

    // Boundary check
    logic out_of_bounds;

    // Interpolated results
    logic [PIXEL_WIDTH+7-1:0] term1, term2, term3, term4;
    logic [PIXEL_WIDTH+14-1:0] interp_result;  // 8+14=22 bits for 4-way MAC

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            out_x      <= '0;
            out_y      <= '0;
            src_re     <= 1'b0;
            flow_re    <= 1'b0;
            warped_we  <= 1'b0;
            corner_idx <= '0;
        end else begin
            src_re    <= 1'b0;
            flow_re   <= 1'b0;
            warped_we <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        state <= READ_FLOW;
                        out_x <= '0;
                        out_y <= '0;
                    end
                end

                READ_FLOW: begin
                    // Read flow vector for current output pixel
                    flow_addr <= out_y * WIDTH + out_x;
                    flow_re   <= 1'b1;
                    state     <= WAIT_FLOW;
                end

                WAIT_FLOW: begin
                    // BRAM read latency (1 cycle)
                    state <= READ_CORNERS;
                end

                READ_CORNERS: begin
                    // Compute warped source coordinates
                    // S8.7 fixed-point: out_x * 128 + flow_u_data
                    src_x_fp <= ($signed({1'b0, out_x}) <<< 7) + flow_u_data;
                    src_y_fp <= ($signed({1'b0, out_y}) <<< 7) + flow_v_data;

                    // Extract integer and fractional parts
                    // Integer: bits [FLOW_WIDTH-1:7]
                    // Fractional: bits [6:0]
                    src_x0 <= src_x_fp[FLOW_WIDTH-1:7];
                    src_y0 <= src_y_fp[FLOW_WIDTH-1:7];
                    src_x1 <= src_x0 + 1;
                    src_y1 <= src_y0 + 1;

                    wx <= src_x_fp[6:0];
                    wy <= src_y_fp[6:0];

                    // Boundary check (clamp to valid range)
                    out_of_bounds <= (src_x0 >= WIDTH) || (src_y0 >= HEIGHT) || ($signed(
                        src_x_fp
                    ) < 0) || ($signed(
                        src_y_fp
                    ) < 0);

                    if (out_of_bounds) begin
                        // Skip interpolation, write black pixel
                        interp_pixel <= '0;
                        state        <= WRITE_PIXEL;
                    end else begin
                        // Read first corner (f00)
                        src_addr   <= src_y0 * WIDTH + src_x0;
                        src_re     <= 1'b1;
                        corner_idx <= 2'b00;
                        state      <= WAIT_READ;
                    end
                end

                WAIT_READ: begin
                    state <= INTERPOLATE;
                end

                INTERPOLATE: begin
                    // Store corner value
                    corners[corner_idx] <= src_pixel_data;

                    // Read next corner
                    case (corner_idx)
                        2'b00: begin  // Read f10 (x+1, y)
                            src_addr   <= src_y0 * WIDTH + src_x1;
                            src_re     <= 1'b1;
                            corner_idx <= 2'b01;
                            state      <= WAIT_READ;
                        end
                        2'b01: begin  // Read f01 (x, y+1)
                            src_addr   <= src_y1 * WIDTH + src_x0;
                            src_re     <= 1'b1;
                            corner_idx <= 2'b10;
                            state      <= WAIT_READ;
                        end
                        2'b10: begin  // Read f11 (x+1, y+1)
                            src_addr   <= src_y1 * WIDTH + src_x1;
                            src_re     <= 1'b1;
                            corner_idx <= 2'b11;
                            state      <= WAIT_READ;
                        end
                        2'b11: begin  // All corners read, compute interpolation
                            // Bilinear interpolation (unoptimized - combinational MAC)
                            // f(x,y) = (1-wx)*(1-wy)*f00 + wx*(1-wy)*f10 +
                            //          (1-wx)*wy*f01 + wx*wy*f11
                            // Weights in 7-bit fixed-point (divide by 128^2 at end)

                            term1 <= (8'd128 - {1'b0, wx}) * (8'd128 - {1'b0, wy}) * corners[0];
                            term2 <= {1'b0, wx} * (8'd128 - {1'b0, wy}) * corners[1];
                            term3 <= (8'd128 - {1'b0, wx}) * {1'b0, wy} * corners[2];
                            term4 <= {1'b0, wx} * {1'b0, wy} * corners[3];

                            interp_result <= term1 + term2 + term3 + term4;

                            // Divide by 128^2 = 16384 (shift right 14 bits)
                            interp_pixel <= interp_result[PIXEL_WIDTH+14-1:14];

                            state <= WRITE_PIXEL;
                        end

                        default: begin
                            state <= IDLE;  // Safety catch
                        end
                    endcase
                end

                WRITE_PIXEL: begin
                    // Write warped pixel to output BRAM
                    warped_addr       <= out_y * WIDTH + out_x;
                    warped_pixel_data <= interp_pixel;
                    warped_we         <= 1'b1;

                    // Increment output position
                    if (out_x == WIDTH - 1) begin
                        out_x <= '0;
                        if (out_y == HEIGHT - 1) begin
                            state <= IDLE;
                        end else begin
                            out_y <= out_y + 1;
                            state <= READ_FLOW;
                        end
                    end else begin
                        out_x <= out_x + 1;
                        state <= READ_FLOW;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    // Done signal (single-cycle pulse when returning to IDLE after completion)
    assign done = (state == IDLE) && (out_y == HEIGHT) && (out_x == 0);

endmodule : frame_warper
