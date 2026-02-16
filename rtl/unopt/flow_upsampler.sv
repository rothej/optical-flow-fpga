/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/flow_upsampler.sv
 *
 * Description: Upsamples flow field by 2x using bilinear interpolation.
 *              Flow magnitudes are scaled proportionally (multiply by 2).
 *
 *              Unoptimized: Combinational 4-way multiply-accumulate (critical path).
 *
 *              Bilinear interpolation formula:
 *                f(x,y) = (1-wx)*(1-wy)*f00 + wx*(1-wy)*f10 +
 *                         (1-wx)*wy*f01 + wx*wy*f11
 *              where wx, wy are fractional offsets (0 or 0.5 for 2x upsampling)
 */

`timescale 1ns / 1ps

module flow_upsampler #(
    parameter int FLOW_WIDTH        = 16,   // S8.7 fixed-point
    parameter int COARSE_WIDTH      = 80,
    parameter int COARSE_HEIGHT     = 60,
    parameter int FINE_WIDTH        = 160,
    parameter int FINE_HEIGHT       = 120,
    parameter int COARSE_ADDR_WIDTH = 16,
    parameter int FINE_ADDR_WIDTH   = 17
) (
    input logic clk,
    input logic rst_n,

    // Control
    input  logic start,
    output logic done,

    // Coarse flow input (BRAM read interface)
    input  logic signed [       FLOW_WIDTH-1:0] coarse_u_data,
    input  logic signed [       FLOW_WIDTH-1:0] coarse_v_data,
    output logic        [COARSE_ADDR_WIDTH-1:0] coarse_addr,
    output logic                                coarse_re,

    // Fine flow output (BRAM write interface)
    output logic signed [     FLOW_WIDTH-1:0] fine_u_data,
    output logic signed [     FLOW_WIDTH-1:0] fine_v_data,
    output logic        [FINE_ADDR_WIDTH-1:0] fine_addr,
    output logic                              fine_we
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE,
        READ_CORNERS,  // Read 4 neighboring coarse pixels
        WAIT_READ,  // Wait for BRAM latency
        INTERPOLATE,  // Compute bilinear interpolation
        WRITE_FINE  // Write upsampled pixel
    } state_e;

    state_e state;

    // Fine pixel counters
    logic [$clog2(FINE_WIDTH)-1:0] fine_x;
    logic [$clog2(FINE_HEIGHT)-1:0] fine_y;

    // Coarse grid coordinates (fine_x/2, fine_y/2)
    logic [$clog2(COARSE_WIDTH)-1:0] coarse_x0, coarse_x1;
    logic [$clog2(COARSE_HEIGHT)-1:0] coarse_y0, coarse_y1;

    // Bilinear interpolation weights (0.0 or 0.5 for 2x upsampling)
    // Represented as 2-bit fractional: 00 (0.0), 10 (0.5)
    logic wx, wy;  // 0 or 1 (maps to 0.0 or 0.5)

    // Storage for 4 corner flow values (f00, f10, f01, f11)
    logic signed [FLOW_WIDTH-1:0] u_corners[4];
    logic signed [FLOW_WIDTH-1:0] v_corners[4];
    logic [1:0] corner_idx;  // 0-3 counter

    // Interpolated results
    logic signed [FLOW_WIDTH-1:0] interp_u, interp_v;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            fine_x     <= '0;
            fine_y     <= '0;
            fine_we    <= 1'b0;
            fine_addr  <= '0;
            coarse_re  <= 1'b0;
            corner_idx <= '0;
        end else begin
            coarse_re <= 1'b0;
            fine_we   <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        state      <= READ_CORNERS;
                        fine_x     <= '0;
                        fine_y     <= '0;
                        corner_idx <= '0;
                    end
                end

                READ_CORNERS: begin
                    // Determine coarse grid neighbors
                    coarse_x0   <= fine_x >> 1;  // fine_x / 2
                    coarse_y0   <= fine_y >> 1;
                    coarse_x1   <= (fine_x >> 1) + ((fine_x < (FINE_WIDTH - 1)) ? 1'b1 : 1'b0);
                    coarse_y1   <= (fine_y >> 1) + ((fine_y < (FINE_HEIGHT - 1)) ? 1'b1 : 1'b0);

                    // Compute interpolation weights
                    wx          <= fine_x[0];  // 0 if even, 1 if odd (maps to 0.0 or 0.5)
                    wy          <= fine_y[0];

                    // Read first corner (f00)
                    coarse_addr <= coarse_y0 * COARSE_WIDTH + coarse_x0;
                    coarse_re   <= 1'b1;
                    corner_idx  <= '0;
                    state       <= WAIT_READ;
                end

                WAIT_READ: begin
                    // BRAM read latency (1 cycle)
                    state <= INTERPOLATE;
                end

                INTERPOLATE: begin
                    // Store corner value
                    u_corners[corner_idx] <= coarse_u_data;
                    v_corners[corner_idx] <= coarse_v_data;

                    // Read next corner
                    case (corner_idx)
                        2'b00: begin  // Read f10 (x+1, y)
                            coarse_addr <= coarse_y0 * COARSE_WIDTH + coarse_x1;
                            coarse_re   <= 1'b1;
                            corner_idx  <= 2'b01;
                            state       <= WAIT_READ;
                        end
                        2'b01: begin  // Read f01 (x, y+1)
                            coarse_addr <= coarse_y1 * COARSE_WIDTH + coarse_x0;
                            coarse_re   <= 1'b1;
                            corner_idx  <= 2'b10;
                            state       <= WAIT_READ;
                        end
                        2'b10: begin  // Read f11 (x+1, y+1)
                            coarse_addr <= coarse_y1 * COARSE_WIDTH + coarse_x1;
                            coarse_re   <= 1'b1;
                            corner_idx  <= 2'b11;
                            state       <= WAIT_READ;
                        end
                        2'b11: begin  // All corners read, compute interpolation
                            state <= WRITE_FINE;
                        end
                        default: begin
                            state <= IDLE;
                        end
                    endcase
                end

                WRITE_FINE: begin
                    // Compute bilinear interpolation
                    // For 2x upsampling, weights are always {0.0, 0.5}
                    // Simplified: interp = (1-wx)*(1-wy)*f00 + wx*(1-wy)*f10 +
                    //                      (1-wx)*wy*f01 + wx*wy*f11

                    logic signed [FLOW_WIDTH-1:0] u_interp_comb, v_interp_comb;

                    // Weight combinations (all possible for wx, wy):
                    // (0,0): 100% f00
                    // (1,0): 50% f00 + 50% f10
                    // (0,1): 50% f00 + 50% f01
                    // (1,1): 25% each

                    case ({
                        wx, wy
                    })
                        2'b00: begin  // (0.0, 0.0)
                            u_interp_comb <= u_corners[0];
                            v_interp_comb <= v_corners[0];
                        end
                        2'b01: begin  // (0.0, 0.5)
                            u_interp_comb <= (u_corners[0] + u_corners[2]) >>> 1;
                            v_interp_comb <= (v_corners[0] + v_corners[2]) >>> 1;
                        end
                        2'b10: begin  // (0.5, 0.0)
                            u_interp_comb <= (u_corners[0] + u_corners[1]) >>> 1;
                            v_interp_comb <= (v_corners[0] + v_corners[1]) >>> 1;
                        end
                        2'b11: begin  // (0.5, 0.5)
                            u_interp_comb <= (u_corners[0] + u_corners[1] +
                                             u_corners[2] + u_corners[3]) >>> 2;
                            v_interp_comb <= (v_corners[0] + v_corners[1] +
                                             v_corners[2] + v_corners[3]) >>> 2;
                        end
                        default: begin
                            u_interp_comb <= 0;
                            v_interp_comb <= 0;
                        end
                    endcase

                    // Scale flow by 2x (motion is proportional to resolution)
                    interp_u    <= u_interp_comb <<< 1;
                    interp_v    <= v_interp_comb <<< 1;

                    // Write to fine grid
                    fine_addr   <= fine_y * FINE_WIDTH + fine_x;
                    fine_u_data <= interp_u;
                    fine_v_data <= interp_v;
                    fine_we     <= 1'b1;

                    // Increment fine pixel position
                    if (fine_x == FINE_WIDTH - 1) begin
                        fine_x <= '0;
                        if (fine_y == FINE_HEIGHT - 1) begin
                            state <= IDLE;  // Done
                        end else begin
                            fine_y <= fine_y + 1;
                            state  <= READ_CORNERS;
                        end
                    end else begin
                        fine_x <= fine_x + 1;
                        state  <= READ_CORNERS;
                    end
                end

                default: begin
                    next_state <= IDLE;
                end
            endcase
        end
    end

    assign done = (state == IDLE) && (fine_y == FINE_HEIGHT - 1) && (fine_x == FINE_WIDTH - 1);

endmodule : flow_upsampler
