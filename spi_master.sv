`timescale 1ns/1ps

module spi_master (
    input logic clk,
    input logic rst,

    input logic start,
    input logic [15:0] tx_data,
    input logic transfer_width,
    input logic [1:0] spi_mode,
    input logic [15:0] clock_divider,

    output logic [15:0] rx_data,
    output logic busy,
    output logic done,
    output logic error,

    output logic sclk,
    output logic mosi,
    input logic miso,
    output logic cs
);

    logic [15:0] tx_shift_reg;
    logic [15:0] rx_shift_reg;

    logic [3:0] bit_count;
    logic [15:0] div_count;
    logic spi_tick;

    logic first_edge;
    logic last_bit;

    logic sample_on_rising;

    assign sample_on_rising =
        ~(spi_mode[1] ^ spi_mode[0]);


    always_comb begin
        if (transfer_width == 1'b0)
            last_bit = (bit_count == 4'd7);
        else
            last_bit = (bit_count == 4'd15);
    end

    // SPI clock divider

    always_ff @(posedge clk) begin
        if (rst) begin
            div_count <= 16'd0;
            spi_tick  <= 1'b0;
        end
        else if (!busy) begin
            div_count <= 16'd0;
            spi_tick  <= 1'b0;
        end
        else if (clock_divider == 16'd0) begin
            div_count <= 16'd0;
            spi_tick  <= 1'b1;
        end
        else if (div_count == clock_divider - 1'b1) begin
            div_count <= 16'd0;
            spi_tick  <= 1'b1;
        end
        else begin
            div_count <= div_count + 1'b1;
            spi_tick  <= 1'b0;
        end
    end

    // SPI Master FSM

    typedef enum logic [2:0] {
        IDLE,
        LOAD,
        TRANSFER,
        FINISH_TRANSFER,
        FINISH
    } state_t;

    state_t state;


    always_ff @(posedge clk) begin

        if (rst) begin

            state <= IDLE;

            busy  <= 1'b0;
            done  <= 1'b0;
            error <= 1'b0;
            cs   <= 1'b1;
            sclk <= 1'b0;
            mosi <= 1'b0;

            rx_data <= 16'd0;
            tx_shift_reg <= 16'd0;
            rx_shift_reg <= 16'd0;
            bit_count <= 4'd0;
            first_edge <= 1'b0;

        end
        else begin

            // done is a one-clock pulse
            done <= 1'b0;
            case (state)
            
                // IDLE
                IDLE: begin
                    busy <= 1'b0;
                    cs   <= 1'b1;
                    
                    // Return SCLK to CPOL idle level
                    sclk <= spi_mode[1];

                    if (start) begin
                        state <= LOAD;
                    end
                end

                // LOAD -------------------------------------------------------------------------
                LOAD: begin
                    busy <= 1'b1;
                    cs   <= 1'b0;

                    // Prepare transmit data
                    if (transfer_width == 1'b0)
                        tx_shift_reg <= {
                            tx_data[7:0],
                            8'd0
                        };
                    else
                        tx_shift_reg <= tx_data;

                    // Clear receive register
                    rx_shift_reg <= 16'd0;
                    bit_count <= 4'd0;

                    // First active edge 
                    first_edge <= 1'b1;

                    // CPHA = 0:
                    // first data bit must already be present before the first active edge.
                    if (spi_mode[0] == 1'b0) begin
                        if (transfer_width == 1'b0)
                            mosi <= tx_data[7];
                        else
                            mosi <= tx_data[15];

                    end

                    // CPHA = 1:
                    // data changes on the first active edge.
                    else begin
                        mosi <= 1'b0;
                    end

                    // SCLK starts at CPOL
                    sclk <= spi_mode[1];

                    state <= TRANSFER;

                end

                // TRANSFER --------------------------------------------------------
                TRANSFER: begin

                    busy <= 1'b1;
                    cs   <= 1'b0;
                    
                    if (spi_tick) begin

                        // SCLK LOW -> HIGH
                        if (sclk == 1'b0) begin
                            sclk <= 1'b1;

                            // Sample on rising edge
                            if (sample_on_rising) begin

                                rx_shift_reg <= {
                                    rx_shift_reg[14:0],
                                    miso
                                };
                                
                                if (last_bit) begin
                                    rx_data <= {
                                        rx_shift_reg[14:0],
                                        miso
                                    };
                                    state <= FINISH_TRANSFER;
                                end
                                else begin
                                    bit_count <= bit_count + 1'b1;
                                end
                            end
                            
                            // Change data on rising edge
                            // CPHA = 1
                            else begin

                                // FIRST active edge:
                                // put MSB on MOSI.
                                // Do NOT shift here.
                                if (first_edge) begin

                                    if (transfer_width == 1'b0)
                                        mosi <= tx_data[7];
                                    else
                                        mosi <= tx_data[15];
                                end
                                
                                // shift to next bit.
                                else begin

                                    tx_shift_reg <= {
                                        tx_shift_reg[14:0],
                                        1'b0
                                    };

                                    mosi <= tx_shift_reg[14];
                                end
                            end
                        end

                        // SCLK HIGH -> LOW
                 
                        else begin

                            sclk <= 1'b0;

                            // Sample on falling edge

                            if (!sample_on_rising) begin

                                rx_shift_reg <= {
                                    rx_shift_reg[14:0],
                                    miso
                                };
                                
                                if (last_bit) begin
                                    rx_data <= {
                                        rx_shift_reg[14:0],
                                        miso
                                    };
                                    state <= FINISH_TRANSFER;
                                end
                                else begin
                                    bit_count <= bit_count + 1'b1;
                                end
                            end


                            // Change data on falling edge
                            // CPHA = 1
                           
                            else begin

                                // FIRST active edge:
                                // This is especially important for
                                // SPI Mode 3 because its first edge is FALLING
                                           
                                if (first_edge) begin
                                    if (transfer_width == 1'b0)
                                        mosi <= tx_data[7];
                                    else
                                        mosi <= tx_data[15];

                                end
                             
                                else begin
                                    tx_shift_reg <= {
                                        tx_shift_reg[14:0],
                                        1'b0
                                    };

                                    mosi <= tx_shift_reg[14];

                                end
                            end
                        end

                        // First edge is handled only once.
                        first_edge <= 1'b0;
                    end
                end
           
                // FINISH TRANSFER
                
                FINISH_TRANSFER: begin

                    busy <= 1'b1;
                    cs   <= 1'b0;

                    // Return SCLK to CPOL idle level
                    sclk <= spi_mode[1];
                    state <= FINISH;
                end

               
                // FINISH
               
                FINISH: begin
                    busy <= 1'b0;
                    cs   <= 1'b1;
                    done <= 1'b1;
                    state <= IDLE;
                end
 
                // SAFETY
               
                default: begin
                    state <= IDLE;
                    busy <= 1'b0;
                    cs   <= 1'b1;
                    sclk <= spi_mode[1];
                    mosi <= 1'b0;
                end
            endcase
        end
    end
endmodule