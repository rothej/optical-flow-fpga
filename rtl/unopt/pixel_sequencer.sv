/*************************************************************************************************
 * Copyright 2026 Joshua Rothe
 * All Rights Reserved Worldwide
 *
 * Licensed under the MIT License (MIT)
 *************************************************************************************************/
/*
 * Filename: rtl/unopt/pixel_sequencer.sv
 *
 * Description: Streams pixels from BRAM to the L-K solver in raster-scan order.
 *              Handles BRAM read latency (1 cycle).
 *              Outputs pixel coordinates for flow write addressing.
 */

`timescale 1ns / 1ps

module pixel_sequencer #(
    parameter int WIDTH      = 320,
    parameter int HEIGHT     = 240,
    parameter int ADDR_WIDTH = 18
) (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      start,
    output logic                      done,
    output logic [    ADDR_WIDTH-1:0] read_addr,
    output logic                      read_enable,
    output logic [ $clog2(WIDTH)-1:0] pixel_x,
    output logic [$clog2(HEIGHT)-1:0] pixel_y,
    output logic                      coord_valid   // Coordinates valid (for flow write)
);

    typedef enum logic [1:0] {
        IDLE,
        READING,
        DONE_ST
    } state_e;

    state_e state;
    localparam int PIXEL_COUNT = WIDTH * HEIGHT;
    logic [ADDR_WIDTH-1:0] pixel_cnt;

    // Coordinate tracking (accounts for 1-cycle BRAM read latency)
    logic [$clog2(WIDTH)-1:0] x_delayed;
    logic [$clog2(HEIGHT)-1:0] y_delayed;
    logic coord_valid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            pixel_cnt     <= '0;
            read_enable   <= 1'b0;
            done          <= 1'b0;
            x_delayed     <= '0;
            y_delayed     <= '0;
            coord_valid_q <= 1'b0;
        end else begin
            done <= 1'b0;  // Single-cycle pulse

            case (state)
                IDLE: begin
                    if (start) begin
                        state         <= READING;
                        pixel_cnt     <= '0;
                        read_enable   <= 1'b1;
                        coord_valid_q <= 1'b0;
                    end
                end

                READING: begin
                    // Delay coordinates by 1 cycle (BRAM latency)
                    x_delayed <= pixel_cnt % WIDTH;
                    y_delayed <= pixel_cnt / WIDTH;
                    coord_valid_q <= read_enable;

                    if (pixel_cnt == (WIDTH * HEIGHT - 1)) begin
                        state       <= DONE_ST;
                        read_enable <= 1'b0;
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                end

                DONE_ST: begin
                    done          <= 1'b1;
                    state         <= IDLE;
                    coord_valid_q <= 1'b0;
                end

                default: begin
                    next_state <= IDLE;
                end
            endcase
        end
    end

    assign read_addr   = pixel_cnt;
    assign pixel_x     = x_delayed;
    assign pixel_y     = y_delayed;
    assign coord_valid = coord_valid_q;

endmodule : pixel_sequencer
