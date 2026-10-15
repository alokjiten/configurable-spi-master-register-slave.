`timescale 1ns/1ps

module spi_top (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic [15:0] tx_data,
    input  logic        transfer_width,
    input  logic [1:0]  spi_mode,
    input  logic [15:0] clock_divider,

    output logic [15:0] rx_data,
    output logic        busy,
    output logic        done,
    output logic        master_error,
    output logic        slave_error,

    output logic        sclk,
    output logic        mosi,
    output logic        miso,
    output logic        cs,

    output logic [7:0]  control_reg,
    output logic [7:0]  status_reg,
    output logic [7:0]  data_reg
);

    // Internal connection from Slave to Master.
    logic slave_miso;

    // SPI MASTER
    spi_master master_inst (
        .clk            (clk),
        .rst            (rst),
        .start          (start),
        .tx_data        (tx_data),
        .transfer_width (transfer_width),
        .spi_mode       (spi_mode),
        .clock_divider  (clock_divider),
        .rx_data        (rx_data),
        .busy           (busy),
        .done           (done),
        .error          (master_error),
        .sclk           (sclk),
        .mosi           (mosi),
        .miso           (slave_miso),
        .cs             (cs)
    );

    // SPI SLAVE
    spi_slave slave_inst (
        .clk         (clk),
        .rst         (rst),
        .sclk        (sclk),
        .cs          (cs),
        .mosi        (mosi),
        .spi_mode    (spi_mode),
        .miso        (slave_miso),
        .control_reg (control_reg),
        .status_reg  (status_reg),
        .data_reg    (data_reg),
        .error       (slave_error)
    );

    // Slave MISO is the external MISO signal.
    assign miso = slave_miso;

endmodule
