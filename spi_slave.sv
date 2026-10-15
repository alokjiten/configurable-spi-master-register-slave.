`timescale 1ns/1ps

module spi_slave (
    input  logic       clk,
    input  logic       rst,

    input  logic       sclk,
    input  logic       cs,
    input  logic       mosi,

    input  logic [1:0] spi_mode,

    output logic       miso,

    output logic [7:0] control_reg,
    output logic [7:0] status_reg,
    output logic [7:0] data_reg,

    output logic       error
);

    // Register addresses

    localparam logic [6:0] ADDR_DEVICE_ID = 7'h00;
    localparam logic [6:0] ADDR_CONTROL   = 7'h01;
    localparam logic [6:0] ADDR_STATUS    = 7'h02;
    localparam logic [6:0] ADDR_DATA      = 7'h03;


    // Fixed Device ID

    localparam logic [7:0] DEVICE_ID = 8'hA5;


    // spi_mode[1] = CPOL
    // spi_mode[0] = CPHA

    // Mode 0 -> sample rising
    // Mode 1 -> sample falling
    // Mode 2 -> sample falling
    // Mode 3 -> sample rising

    logic sample_on_rising;

    assign sample_on_rising =
        ~(spi_mode[1] ^ spi_mode[0]);

    // Previous SCLK and CS
  
    logic sclk_d;
    logic cs_d;

    // Edge detection

    logic sclk_rising;
    logic sclk_falling;
    logic cs_falling;
    logic cs_rising;

    assign sclk_rising  =  sclk & ~sclk_d;
    assign sclk_falling = ~sclk &  sclk_d;
    assign cs_falling   = ~cs & cs_d;
    assign cs_rising    =  cs & ~cs_d;

    // SPI shift registers
    logic [15:0] rx_shift_reg;
    logic [15:0] tx_shift_reg;

    // Bit counter
    logic [4:0] bit_count;
 
    // Transaction active
    logic transaction_active;

    // Decoded command
    logic       rw;
    logic [6:0] register_address;

    always_ff @(posedge clk) begin
    
        if (rst) begin
            sclk_d <= 1'b0;
            cs_d   <= 1'b1;

            rx_shift_reg <= 16'h0000;
            tx_shift_reg <= 16'h0000;

            bit_count <= 5'd0;

            transaction_active <= 1'b0;

            rw               <= 1'b0;
            register_address <= 7'h00;
            
            // MISO
            miso <= 1'b0;
            control_reg <= 8'h00;
            status_reg  <= 8'h01;
            data_reg    <= 8'h00;

            error <= 1'b0;
        end

        // NORMAL OPERATION

        else begin

            sclk_d <= sclk;
            cs_d   <= cs;

            // CS FALLING EDGE

            if (cs_falling) begin

                transaction_active <= 1'b1;

                bit_count <= 5'd0;

                rx_shift_reg <= 16'h0000;
                tx_shift_reg <= 16'h0000;

                rw               <= 1'b0;
                register_address <= 7'h00;

                miso <= 1'b0;

                error <= 1'b0;

            end

            // CS RISING EDGE

            else if (cs_rising) begin

                transaction_active <= 1'b0;

                if (bit_count != 5'd16) begin
                    error <= 1'b1;
                end
            end

            // ACTIVE SPI TRANSACTION
            else if (transaction_active) begin

                // RISING EDGE
                if (sclk_rising) begin

                    // SAMPLE ON RISING EDGE
                    // Modes 0 and 3

                    if (sample_on_rising) begin
                        if (bit_count < 5'd16) begin

                            // Receive one MOSI bit
                            rx_shift_reg <= {
                                rx_shift_reg[14:0],
                                mosi
                            };

                            // 8th sampled bit
                            if (bit_count == 5'd7) begin

                                // First received bit = R/W
                                rw <= rx_shift_reg[6];

                                // Remaining 7 bits = address
                                register_address <= {
                                    rx_shift_reg[5:0],
                                    mosi
                                };

                                // READ operation
                                if (rx_shift_reg[6] == 1'b1) begin

                                    case ({
                                        rx_shift_reg[5:0],
                                        mosi
                                    })

                                        // Device ID
                                        ADDR_DEVICE_ID: begin

                                            tx_shift_reg <= {
                                                DEVICE_ID,
                                                8'h00
                                            };

                                        end

                                        // Control
                                        ADDR_CONTROL: begin

                                            tx_shift_reg <= {
                                                control_reg,
                                                8'h00
                                            };

                                        end

                                        // Status
                                        ADDR_STATUS: begin

                                            tx_shift_reg <= {
                                                status_reg,
                                                8'h00
                                            };

                                        end

                                        // Data
                                        ADDR_DATA: begin

                                            tx_shift_reg <= {
                                                data_reg,
                                                8'h00
                                            };

                                        end

                                        // Invalid address
                                        default: begin

                                            tx_shift_reg <= 16'h0000;
                                            error <= 1'b1;

                                        end
                                    endcase
                                end
                            end

                            // 16th sampled bit
                            if (bit_count == 5'd15) begin

                                // WRITE TRANSACTION
                                if (rx_shift_reg[14] == 1'b0) begin
                                    case (rx_shift_reg[13:7])

                                        // Control register
                                        ADDR_CONTROL: begin
                                            control_reg <= {
                                                rx_shift_reg[6:0],
                                                mosi
                                            };
                                        end

                                        // Data register
                                        ADDR_DATA: begin
                                            data_reg <= {
                                                rx_shift_reg[6:0],
                                                mosi
                                            };
                                        end

                                        // Device ID is read-only
                                        ADDR_DEVICE_ID: begin
                                            error <= 1'b1;
                                        end

                                        // Status is read-only
                                        ADDR_STATUS: begin
                                            error <= 1'b1;
                                        end

                                        // Invalid address
                                        default: begin
                                            error <= 1'b1;
                                        end
                                    endcase
                                end
                            end
                            
                            // Increment number of sampled bits
                            bit_count <= bit_count + 1'b1;

                        end

                        else begin

                            // More than 16 bits received
                            error <= 1'b1;
                        end
                    end

                    // CHANGE MISO ON RISING EDGE
                    // Modes 1 and 2
                    
                    else begin

                        miso <= tx_shift_reg[15];

                        tx_shift_reg <= {
                            tx_shift_reg[14:0],
                            1'b0
                        };

                    end

                end

                // FALLING EDGE
                else if (sclk_falling) begin

                    // SAMPLE ON FALLING EDGE
                    // Modes 1 and 2
                    if (!sample_on_rising) begin

                        if (bit_count < 5'd16) begin

                            // Receive one MOSI bit
                            rx_shift_reg <= {
                                rx_shift_reg[14:0],
                                mosi
                            };

                            // 8th sampled bit
                            if (bit_count == 5'd7) begin

                                // R/W
                                rw <= rx_shift_reg[6];

                                // Address
                                register_address <= {
                                    rx_shift_reg[5:0],
                                    mosi
                                };

                                // READ operation ------------------------------------
                                if (rx_shift_reg[6] == 1'b1) begin

                                    case ({
                                        rx_shift_reg[5:0],
                                        mosi
                                    })

                                        // Device ID
                                        ADDR_DEVICE_ID: begin

                                            tx_shift_reg <= {
                                                DEVICE_ID,
                                                8'h00
                                            };

                                        end

                                        // Control
                                        ADDR_CONTROL: begin

                                            tx_shift_reg <= {
                                                control_reg,
                                                8'h00
                                            };

                                        end

                                        // Status
                                        ADDR_STATUS: begin

                                            tx_shift_reg <= {
                                                status_reg,
                                                8'h00
                                            };

                                        end

                                        // Data
                                        ADDR_DATA: begin

                                            tx_shift_reg <= {
                                                data_reg,
                                                8'h00
                                            };

                                        end

                                        // Invalid address
                                        default: begin

                                            tx_shift_reg <= 16'h0000;

                                            error <= 1'b1;

                                        end

                                    endcase

                                end

                            end

                            // 16th sampled bit
                            if (bit_count == 5'd15) begin
                            
                                // WRITE ------------------------------------------------
                                if (rx_shift_reg[14] == 1'b0) begin

                                    case (rx_shift_reg[13:7])

                                        // Control
                                        ADDR_CONTROL: begin

                                            control_reg <= {
                                                rx_shift_reg[6:0],
                                                mosi
                                            };

                                        end

                                        // Data
                                        ADDR_DATA: begin

                                            data_reg <= {
                                                rx_shift_reg[6:0],
                                                mosi
                                            };

                                        end

                                        // Device ID is read-only
                                        ADDR_DEVICE_ID: begin

                                            error <= 1'b1;

                                        end

                                        // Status is read-only
                                        ADDR_STATUS: begin

                                            error <= 1'b1;

                                        end

                                        // Invalid address
                                        default: begin

                                            error <= 1'b1;

                                        end

                                    endcase

                                end

                            end

                            // Increment sample counter
                            bit_count <= bit_count + 1'b1;

                        end

                        else begin

                            // More than 16 bits
                            error <= 1'b1;

                        end

                    end

                    // CHANGE MISO ON FALLING EDGE
                    // Modes 0 and 3

                    else begin

                        miso <= tx_shift_reg[15];

                        tx_shift_reg <= {
                            tx_shift_reg[14:0],
                            1'b0
                        };

                    end

                end

            end

        end

    end

endmodule