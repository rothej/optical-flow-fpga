/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/pyramid_builder.sv
 *
 * Description: Builds 3-level Gaussian pyramid via iterative 2x2 averaging.
 *              - Level 2 (L2): 320×240 (full resolution, direct copy)
 *              - Level 1 (L1): 160×120 (2x2 average from L2)
 *              - Level 0 (L0): 80×60 (2x2 average from L1)
 *
 *              Unoptimized: Sequential processing (one level at a time).
 *              Downsampling reads from BRAM source, accumulates 2x2 blocks,
 *              and writes averaged result to destination BRAM.
 */

`timescale 1ns / 1ps

module pyramid_builder #(
    parameter int PIXEL_WIDTH = 8,
    parameter int L2_WIDTH    = 320, // Full resolution
    parameter int L2_HEIGHT   = 240,
    parameter int L1_WIDTH    = 160, // Half resolution
    parameter int L1_HEIGHT   = 120,
    parameter int L0_WIDTH    = 80,  // Quarter resolution
    parameter int L0_HEIGHT   = 60
) (
    input logic clk,
    input logic rst_n,

    // Input: Full-resolution frame (streaming from frame buffer)
    input logic [PIXEL_WIDTH-1:0] pixel_in,
    input logic                   pixel_valid,

    // Control
    input  logic start,
    output logic done,

    // Pyramid level outputs (BRAM write interface)
    output logic [PIXEL_WIDTH-1:0] pyr_l0_data,
    output logic [           15:0] pyr_l0_addr,  // 80*60 = 4800 pixels
    output logic                   pyr_l0_we,

    output logic [PIXEL_WIDTH-1:0] pyr_l1_data,
    output logic [           16:0] pyr_l1_addr,  // 160*120 = 19200 pixels
    output logic                   pyr_l1_we,

    output logic [PIXEL_WIDTH-1:0] pyr_l2_data,
    output logic [           17:0] pyr_l2_addr,  // 320*240 = 76800 pixels
    output logic                   pyr_l2_we,

    // BRAM read interface for downsampling (read from L2, then L1)
    input  logic [PIXEL_WIDTH-1:0] src_read_data,
    output logic [           17:0] src_read_addr,   // Max 18 bits for L2
    output logic                   src_read_enable,

    // State
    output logic [1:0] current_level  // 0=L2, 1=L1, 2=L0, 3=DONE
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE,
        BUILD_L2,  // Store full-res frame
        BUILD_L1,  // Downsample L2 -> L1
        BUILD_L0,  // Downsample L1 -> L0
        DONE_ST
    } state_e;

    state_e state, next_state;

    // Pixel counters
    logic [$clog2(L2_WIDTH*L2_HEIGHT)-1:0] pixel_cnt_l2;
    logic [$clog2(L1_WIDTH*L1_HEIGHT)-1:0] pixel_cnt_l1;
    logic [$clog2(L0_WIDTH*L0_HEIGHT)-1:0] pixel_cnt_l0;

    // 2×2 block accumulation
    logic [PIXEL_WIDTH+1:0] accum_2x2;  // Holds sum of 4 pixels (need +2 bits)
    logic [1:0] block_pixel_cnt;  // 0-3 counter for pixels within 2x2 block
    logic [PIXEL_WIDTH-1:0] block_avg;  // Averaged value (accum_2x2 >> 2)

    // Downsampling coordinate tracking
    logic [$clog2(L2_WIDTH)-1:0] src_x;
    logic [$clog2(L2_HEIGHT)-1:0] src_y;
    logic [1:0] block_x, block_y;  // 0-1 position within 2x2 block

    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (start) next_state = BUILD_L2;
            end

            BUILD_L2: begin
                if (pixel_cnt_l2 == (L2_WIDTH * L2_HEIGHT - 1) && pixel_valid) begin
                    next_state = BUILD_L1;
                end
            end

            BUILD_L1: begin
                if (pixel_cnt_l1 == (L1_WIDTH * L1_HEIGHT - 1) && pyr_l1_we) begin
                    next_state = BUILD_L0;
                end
            end

            BUILD_L0: begin
                if (pixel_cnt_l0 == (L0_WIDTH * L0_HEIGHT - 1) && pyr_l0_we) begin
                    next_state = DONE_ST;
                end
            end

            DONE_ST: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // =========================================================================
    // Level 2 (Full Resolution) - Direct Copy
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_cnt_l2 <= '0;
            pyr_l2_we    <= 1'b0;
            pyr_l2_data  <= '0;
            pyr_l2_addr  <= '0;
        end else begin
            if (state == BUILD_L2 && pixel_valid) begin
                pyr_l2_data  <= pixel_in;
                pyr_l2_addr  <= pixel_cnt_l2;
                pyr_l2_we    <= 1'b1;
                pixel_cnt_l2 <= pixel_cnt_l2 + 1;
            end else begin
                pyr_l2_we <= 1'b0;
                if (state == IDLE) pixel_cnt_l2 <= '0;
            end
        end
    end

    // =========================================================================
    // Level 1 (Half Resolution) - 2x2 Average from L2
    // =========================================================================
    typedef enum logic [2:0] {
        L1_IDLE,
        L1_READ_BLOCK,  // Read 4 pixels from L2 (2x2 block)
        L1_WAIT_READ,   // Wait for BRAM read latency
        L1_ACCUMULATE,  // Sum 4 pixels
        L1_WRITE_AVG    // Write averaged pixel to L1
    } l1_state_e;

    l1_state_e l1_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l1_state        <= L1_IDLE;
            pixel_cnt_l1    <= '0;
            pyr_l1_we       <= 1'b0;
            pyr_l1_data     <= '0;
            pyr_l1_addr     <= '0;
            accum_2x2       <= '0;
            block_pixel_cnt <= '0;
            src_x           <= '0;
            src_y           <= '0;
            block_x         <= '0;
            block_y         <= '0;
            src_read_enable <= 1'b0;
            src_read_addr   <= '0;
        end else begin
            pyr_l1_we       <= 1'b0;
            src_read_enable <= 1'b0;

            case (l1_state)
                L1_IDLE: begin
                    if (state == BUILD_L1) begin
                        l1_state        <= L1_READ_BLOCK;
                        src_x           <= '0;
                        src_y           <= '0;
                        block_x         <= '0;
                        block_y         <= '0;
                        accum_2x2       <= '0;
                        block_pixel_cnt <= '0;
                    end
                end

                L1_READ_BLOCK: begin
                    // Calculate source address: (src_y*2 + block_y) * L2_WIDTH + (src_x*2 + block_x)
                    src_read_addr <= ((src_y << 1) + block_y) * L2_WIDTH + ((src_x << 1) + block_x);
                    src_read_enable <= 1'b1;
                    l1_state <= L1_WAIT_READ;
                end

                L1_WAIT_READ: begin
                    // BRAM has 1-cycle read latency (registered output)
                    l1_state <= L1_ACCUMULATE;
                end

                L1_ACCUMULATE: begin
                    // Add pixel to accumulator
                    accum_2x2       <= accum_2x2 + src_read_data;
                    block_pixel_cnt <= block_pixel_cnt + 1;

                    // Move to next pixel in 2x2 block
                    if (block_x == 1 && block_y == 1) begin
                        // Block complete, write averaged value
                        block_x  <= '0;
                        block_y  <= '0;
                        l1_state <= L1_WRITE_AVG;
                    end else begin
                        if (block_x == 1) begin
                            block_x <= '0;
                            block_y <= block_y + 1;
                        end else begin
                            block_x <= block_x + 1;
                        end
                        l1_state <= L1_READ_BLOCK;
                    end
                end

                L1_WRITE_AVG: begin
                    // Divide by 4 (right shift 2) and write to L1
                    pyr_l1_data     <= accum_2x2[PIXEL_WIDTH+1:2];  // Truncate to 8 bits
                    pyr_l1_addr     <= pixel_cnt_l1;
                    pyr_l1_we       <= 1'b1;
                    pixel_cnt_l1    <= pixel_cnt_l1 + 1;

                    // Reset accumulator for next block
                    accum_2x2       <= '0;
                    block_pixel_cnt <= '0;

                    // Move to next output pixel position
                    if (src_x == L1_WIDTH - 1) begin
                        src_x <= '0;
                        if (src_y == L1_HEIGHT - 1) begin
                            // Level 1 complete
                            l1_state <= L1_IDLE;
                        end else begin
                            src_y    <= src_y + 1;
                            l1_state <= L1_READ_BLOCK;
                        end
                    end else begin
                        src_x    <= src_x + 1;
                        l1_state <= L1_READ_BLOCK;
                    end
                end

                default: begin
                    next_state <= IDLE;
                end
            endcase

            // Reset on state change
            if (state == IDLE) begin
                l1_state     <= L1_IDLE;
                pixel_cnt_l1 <= '0;
            end
        end
    end

    // =========================================================================
    // Level 0 (Quarter Resolution) - 2×2 Average from L1
    // =========================================================================
    // Similar FSM as L1, but reads from L1 instead of L2
    typedef enum logic [2:0] {
        L0_IDLE,
        L0_READ_BLOCK,
        L0_WAIT_READ,
        L0_ACCUMULATE,
        L0_WRITE_AVG
    } l0_state_e;

    l0_state_e l0_state;
    logic [PIXEL_WIDTH+1:0] l0_accum_2x2;
    logic [1:0] l0_block_pixel_cnt;
    logic [$clog2(L1_WIDTH)-1:0] l0_src_x;
    logic [$clog2(L1_HEIGHT)-1:0] l0_src_y;
    logic [1:0] l0_block_x, l0_block_y;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l0_state           <= L0_IDLE;
            pixel_cnt_l0       <= '0;
            pyr_l0_we          <= 1'b0;
            pyr_l0_data        <= '0;
            pyr_l0_addr        <= '0;
            l0_accum_2x2       <= '0;
            l0_block_pixel_cnt <= '0;
            l0_src_x           <= '0;
            l0_src_y           <= '0;
            l0_block_x         <= '0;
            l0_block_y         <= '0;
        end else begin
            pyr_l0_we <= 1'b0;

            case (l0_state)
                L0_IDLE: begin
                    if (state == BUILD_L0) begin
                        l0_state           <= L0_READ_BLOCK;
                        l0_src_x           <= '0;
                        l0_src_y           <= '0;
                        l0_block_x         <= '0;
                        l0_block_y         <= '0;
                        l0_accum_2x2       <= '0;
                        l0_block_pixel_cnt <= '0;
                    end
                end

                L0_READ_BLOCK: begin
                    // Read from L1 (source for L0 downsampling)
                    // Note: src_read_addr is shared, but L1 FSM is idle during BUILD_L0
                    src_read_addr   <= ((l0_src_y << 1) + l0_block_y) * L1_WIDTH +
                                       ((l0_src_x << 1) + l0_block_x);
                    src_read_enable <= 1'b1;
                    l0_state <= L0_WAIT_READ;
                end

                L0_WAIT_READ: begin
                    l0_state <= L0_ACCUMULATE;
                end

                L0_ACCUMULATE: begin
                    l0_accum_2x2       <= l0_accum_2x2 + src_read_data;
                    l0_block_pixel_cnt <= l0_block_pixel_cnt + 1;

                    if (l0_block_x == 1 && l0_block_y == 1) begin
                        l0_block_x <= '0;
                        l0_block_y <= '0;
                        l0_state   <= L0_WRITE_AVG;
                    end else begin
                        if (l0_block_x == 1) begin
                            l0_block_x <= '0;
                            l0_block_y <= l0_block_y + 1;
                        end else begin
                            l0_block_x <= l0_block_x + 1;
                        end
                        l0_state <= L0_READ_BLOCK;
                    end
                end

                L0_WRITE_AVG: begin
                    pyr_l0_data        <= l0_accum_2x2[PIXEL_WIDTH+1:2];
                    pyr_l0_addr        <= pixel_cnt_l0;
                    pyr_l0_we          <= 1'b1;
                    pixel_cnt_l0       <= pixel_cnt_l0 + 1;

                    l0_accum_2x2       <= '0;
                    l0_block_pixel_cnt <= '0;

                    if (l0_src_x == L0_WIDTH - 1) begin
                        l0_src_x <= '0;
                        if (l0_src_y == L0_HEIGHT - 1) begin
                            l0_state <= L0_IDLE;
                        end else begin
                            l0_src_y <= l0_src_y + 1;
                            l0_state <= L0_READ_BLOCK;
                        end
                    end else begin
                        l0_src_x <= l0_src_x + 1;
                        l0_state <= L0_READ_BLOCK;
                    end
                end

                default: begin
                    next_state <= IDLE;
                end
            endcase

            if (state == IDLE) begin
                l0_state     <= L0_IDLE;
                pixel_cnt_l0 <= '0;
            end
        end
    end

    // Done signal
    assign done = (state == DONE_ST);

    // Export current level for debugging
    always_comb begin
        case (state)
            BUILD_L2: current_level = 2'b00;
            BUILD_L1: current_level = 2'b01;
            BUILD_L0: current_level = 2'b10;
            default:  current_level = 2'b11;  // IDLE/DONE
        endcase
    end

endmodule : pyramid_builder
