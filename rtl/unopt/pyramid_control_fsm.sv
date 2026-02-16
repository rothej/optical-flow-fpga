/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/pyramid_control_fsm.sv
 *
 * Description: Top-level FSM orchestrating 3-level pyramidal Lucas-Kanade.
 *
 *              Stages:
 *              1. BUILD_PYRAMID - Downsample frames to L0, L1, L2
 *              2. SOLVE_L0      - Run L-K on 80x60 coarsest level
 *              3. UPSAMPLE_L0   - 2x upsample flow to 160x120
 *              4. SOLVE_L1      - Run L-K on 160x120
 *              5. UPSAMPLE_L1   - 2x upsample flow to 320x240
 *              6. SOLVE_L2      - Run L-K on full 320x240 resolution
 *              7. DONE
 */

`timescale 1ns / 1ps

module pyramid_control_fsm #(
    parameter int IMAGE_WIDTH  = 320,
    parameter int IMAGE_HEIGHT = 240
) (
    input logic clk,
    input logic rst_n,

    output logic warp_start,
    input logic warp_done,
    output logic [1:0] warp_level,  // 0=L1, 1=L2

    output logic accum_start,
    input logic accum_done,
    output logic [1:0] accum_level,  // 0=L1, 1=L2

    output logic [3:0] current_state,  // For memory read prioritization

    // Control interface
    input  logic start,
    output logic busy,
    output logic done,

    // Submodule control signals
    output logic pyramid_build_start,
    input  logic pyramid_build_done,

    output logic       lk_solve_start,
    input  logic       lk_solve_done,
    output logic [1:0] lk_level,        // 0=L0, 1=L1, 2=L2

    output logic upsample_start,
    input logic upsample_done,
    output logic [1:0] upsample_level  // 0=L0->L1, 1=L1->L2
);

    typedef enum logic [3:0] {
        IDLE,
        BUILD_PYRAMID,
        SOLVE_L0,
        UPSAMPLE_L0,
        WARP_L1,
        SOLVE_L1,
        ACCUM_L1,
        UPSAMPLE_L1,
        WARP_L2,
        SOLVE_L2,
        ACCUM_L2,
        DONE_ST
    } state_e;

    state_e state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    assign current_state = state;

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (start) begin
                    next_state = BUILD_PYRAMID;
                end
            end
            BUILD_PYRAMID: begin
                if (pyramid_build_done) begin
                    next_state = SOLVE_L0;
                end
            end
            SOLVE_L0: begin
                if (lk_solve_done) begin
                    next_state = UPSAMPLE_L0;
                end
            end
            UPSAMPLE_L0: begin
                if (upsample_done) begin
                    next_state = WARP_L1;
                end
            end
            WARP_L1: begin
                if (warp_done) begin
                    next_state = SOLVE_L1;
                end
            end
            SOLVE_L1: begin
                if (lk_solve_done) begin
                    next_state = ACCUM_L1;
                end
            end
            ACCUM_L1: begin
                if (accum_done) begin
                    next_state = UPSAMPLE_L1;
                end
            end
            UPSAMPLE_L1: begin
                if (upsample_done) begin
                    next_state = WARP_L2;
                end
            end
            WARP_L2: begin
                if (warp_done) begin
                    next_state = SOLVE_L2;
                end
            end
            SOLVE_L2: begin
                if (lk_solve_done) begin
                    next_state = ACCUM_L2;
                end
            end
            ACCUM_L2: begin
                if (accum_done) begin
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pyramid_build_start <= 1'b0;
            lk_solve_start      <= 1'b0;
            upsample_start      <= 1'b0;
            lk_level            <= 2'b00;
            upsample_level      <= 2'b00;
            busy                <= 1'b0;
            done                <= 1'b0;
            warp_start          <= 1'b0;
            warp_level          <= 2'b00;
            accum_start         <= 1'b0;
            accum_level         <= 2'b00;
        end else begin
            pyramid_build_start <= 1'b0;
            lk_solve_start      <= 1'b0;
            upsample_start      <= 1'b0;
            done                <= 1'b0;
            warp_start          <= 1'b0;
            accum_start         <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                end
                BUILD_PYRAMID: begin
                    busy <= 1'b1;
                    if (state != next_state) begin
                        pyramid_build_start <= 1'b1;
                    end
                end
                SOLVE_L0: begin
                    lk_level <= 2'b00;
                    if (state != next_state) lk_solve_start <= 1'b1;
                end
                UPSAMPLE_L0: begin
                    upsample_level <= 2'b00;
                    if (state != next_state) begin
                        upsample_start <= 1'b1;
                    end
                end
                WARP_L1: begin
                    warp_level <= 2'b00;
                    if (state != next_state) begin
                        warp_start <= 1'b1;
                    end
                end
                SOLVE_L1: begin
                    lk_level <= 2'b01;
                    if (state != next_state) begin
                        lk_solve_start <= 1'b1;
                    end
                end
                ACCUM_L1: begin
                    accum_level <= 2'b00;
                    if (state != next_state) begin
                        accum_start <= 1'b1;
                    end
                end
                UPSAMPLE_L1: begin
                    upsample_level <= 2'b01;
                    if (state != next_state) begin
                        upsample_start <= 1'b1;
                    end
                end
                WARP_L2: begin
                    warp_level <= 2'b01;
                    if (state != next_state) begin
                        warp_start <= 1'b1;
                    end
                end
                SOLVE_L2: begin
                    lk_level <= 2'b10;
                    if (state != next_state) begin
                        lk_solve_start <= 1'b1;
                    end
                end
                ACCUM_L2: begin
                    accum_level <= 2'b01;
                    if (state != next_state) begin
                        accum_start <= 1'b1;
                    end
                end
                DONE_ST: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
                default: begin
                    next_state <= IDLE;
                end
            endcase
        end
    end

endmodule : pyramid_control_fsm
