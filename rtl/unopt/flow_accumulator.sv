/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/flow_accumulator.sv
 *
 * Description: Accumulates upsampled base flow with residual flow.
 *              Self-sequencing - iterates through all pixels independently.
 *
 *              Reads both base flow (upsampled) and residual flow (from solver),
 *              adds them, and writes accumulated result back to base flow memory.
 */

`timescale 1ns / 1ps

module flow_accumulator #(
    parameter int FLOW_WIDTH = 16,
    parameter int WIDTH      = 160,
    parameter int HEIGHT     = 120,
    parameter int ADDR_WIDTH = 17
) (
    input logic clk,
    input logic rst_n,

    // Control
    input  logic start,
    output logic done,

    // Base flow memory (read upsampled flow, write accumulated result)
    input  logic signed [FLOW_WIDTH-1:0] base_flow_u_data,
    input  logic signed [FLOW_WIDTH-1:0] base_flow_v_data,
    output logic        [ADDR_WIDTH-1:0] base_flow_addr,
    output logic                         base_flow_re,
    output logic signed [FLOW_WIDTH-1:0] accum_flow_u_data,
    output logic signed [FLOW_WIDTH-1:0] accum_flow_v_data,
    output logic        [ADDR_WIDTH-1:0] accum_flow_addr,
    output logic                         accum_flow_we,

    // Residual flow memory (read solver output)
    input  logic signed [FLOW_WIDTH-1:0] residual_flow_u_data,
    input  logic signed [FLOW_WIDTH-1:0] residual_flow_v_data,
    output logic        [ADDR_WIDTH-1:0] residual_flow_addr,
    output logic                         residual_flow_re
);

    localparam int TOTAL_PIXELS = WIDTH * HEIGHT;

    typedef enum logic [2:0] {
        IDLE,
        READ_FLOWS,   // Read both base and residual
        WAIT_READ,    // Wait for BRAM latency (1 cycle)
        ACCUMULATE,   // Add flows
        WRITE_RESULT  // Write accumulated flow back
    } state_t;

    state_t state;
    logic [ADDR_WIDTH-1:0] pixel_addr;

    // Buffered flow values (captured after read latency)
    logic signed [FLOW_WIDTH-1:0] base_u_buf, base_v_buf;
    logic signed [FLOW_WIDTH-1:0] residual_u_buf, residual_v_buf;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            pixel_addr       <= '0;
            base_flow_re     <= 1'b0;
            residual_flow_re <= 1'b0;
            accum_flow_we    <= 1'b0;
            done             <= 1'b0;
        end else begin
            // Clear control signals
            base_flow_re     <= 1'b0;
            residual_flow_re <= 1'b0;
            accum_flow_we    <= 1'b0;
            done             <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        state      <= READ_FLOWS;
                        pixel_addr <= '0;
                    end
                end

                READ_FLOWS: begin
                    // Issue reads to both memories
                    base_flow_addr     <= pixel_addr;
                    residual_flow_addr <= pixel_addr;
                    base_flow_re       <= 1'b1;
                    residual_flow_re   <= 1'b1;
                    state              <= WAIT_READ;
                end

                WAIT_READ: begin
                    // Capture data after 1-cycle BRAM latency
                    base_u_buf     <= base_flow_u_data;
                    base_v_buf     <= base_flow_v_data;
                    residual_u_buf <= residual_flow_u_data;
                    residual_v_buf <= residual_flow_v_data;
                    state          <= ACCUMULATE;
                end

                ACCUMULATE: begin
                    // Add flows (base + residual)
                    accum_flow_u_data <= base_u_buf + residual_u_buf;
                    accum_flow_v_data <= base_v_buf + residual_v_buf;
                    state             <= WRITE_RESULT;
                end

                WRITE_RESULT: begin
                    // Write accumulated flow back to base memory
                    accum_flow_addr <= pixel_addr;
                    accum_flow_we   <= 1'b1;

                    // Check if done
                    if (pixel_addr == TOTAL_PIXELS - 1) begin
                        state <= IDLE;
                        done  <= 1'b1;
                    end else begin
                        pixel_addr <= pixel_addr + 1;
                        state      <= READ_FLOWS;
                    end
                end

                default: begin
                    next_state <= IDLE;
                end
            endcase
        end
    end

endmodule : flow_accumulator
