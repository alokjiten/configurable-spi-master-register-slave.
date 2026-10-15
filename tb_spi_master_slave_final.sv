`timescale 1ns/1ps

module tb_spi_master_slave;

    // System clock and reset
    logic clk;
    logic rst;

    // Master inputs
    logic        start;
    logic [15:0] tx_data;
    logic        transfer_width;
    logic [1:0]  spi_mode;
    logic [15:0] clock_divider;

    // Master outputs
    logic [15:0] rx_data;
    logic busy;
    logic done;
    logic master_error;
    logic sclk;
    logic mosi;
    logic cs;

    // Main SPI slave
    logic slave_miso;
    logic slave_error;
    logic [7:0] control_reg;
    logic [7:0] status_reg;
    logic [7:0] data_reg;

    // Testbench interface muxing
    logic fake_mode;
    logic early_cs_force;
    logic slave_cs;

    assign slave_cs = (fake_mode || early_cs_force) ? 1'b1 : cs;

    // In normal tests MISO comes from the real slave.
    // In 8-bit/divider tests MISO comes from the simple test model.
    logic fake_miso;
    assign miso = fake_mode ? fake_miso : slave_miso;

    // Test counters
    integer pass_count;
    integer fail_count;

    // Main SPI MASTER
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
        .miso           (miso),
        .cs             (cs)
    );

    // Main SPI SLAVE
    spi_slave slave_inst (
        .clk            (clk),
        .rst            (rst),
        .sclk           (sclk),
        .cs             (slave_cs),
        .mosi           (mosi),
        .spi_mode       (spi_mode),
        .miso           (slave_miso),
        .control_reg    (control_reg),
        .status_reg     (status_reg),
        .data_reg       (data_reg),
        .error          (slave_error)
    );

    // Separate slave used only for incorrect-clock-count test.
    // This allows the testbench to deliberately generate 17 clocks without fighting the real SPI master.

    logic count_sclk;
    logic count_cs;
    logic count_mosi;
    logic count_miso;
    logic count_slave_error;
    logic [7:0] count_control_reg;
    logic [7:0] count_status_reg;
    logic [7:0] count_data_reg;

    spi_slave count_slave_inst (
        .clk            (clk),
        .rst            (rst),
        .sclk           (count_sclk),
        .cs             (count_cs),
        .mosi           (count_mosi),
        .spi_mode       (2'b00),
        .miso           (count_miso),
        .control_reg    (count_control_reg),
        .status_reg     (count_status_reg),
        .data_reg       (count_data_reg),
        .error          (count_slave_error)
    );

    // 100 MHz system clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Simple 8-bit fake SPI slave, Used to verify Master transfer_width = 8.
    // Mode 0 is used here.
    
    logic fake_sclk_d;
    logic fake_cs_d;
    logic [7:0] fake_tx;
    integer fake_bit_count;

    wire fake_sclk_rising  =  sclk & ~fake_sclk_d;
    wire fake_sclk_falling = ~sclk &  fake_sclk_d;
    wire fake_cs_falling   = ~cs   &  fake_cs_d;
    wire fake_cs_rising    =  cs   & ~fake_cs_d;

    always_ff @(posedge clk) begin
        if (rst) begin
            fake_sclk_d  <= 1'b0;
            fake_cs_d    <= 1'b1;
            fake_tx      <= 8'hA6;
            fake_bit_count <= 0;
            fake_miso    <= 1'b0;
        end
        else if (fake_mode) begin
            fake_sclk_d <= sclk;
            fake_cs_d   <= cs;

            if (fake_cs_falling) begin
                fake_tx        <= 8'hA6;
                fake_bit_count <= 0;
                
                // Mode 0: first MISO bit must be ready before the first rising sample edge.
     
                fake_miso      <= 1'b1;
            end
            else if (fake_cs_rising) begin
                fake_miso <= 1'b0;
            end
            else if (!cs) begin
                if (fake_sclk_rising) begin
                    if (fake_bit_count < 8)
                        fake_bit_count <= fake_bit_count + 1;
                end
                else if (fake_sclk_falling) begin
                    if (fake_bit_count < 8)
                        fake_miso <= fake_tx[7-fake_bit_count];
                end
            end
        end
        else begin
            fake_sclk_d <= sclk;
            fake_cs_d   <= cs;
            fake_miso   <= 1'b0;
            fake_bit_count <= 0;
        end
    end

    // Common start pulse
    task automatic start_transaction(input logic [15:0] word);
        begin
            tx_data = word;

            @(negedge clk);
            start = 1'b1;

            @(posedge clk);
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    // Wait for transaction completion
    task automatic wait_transaction;
        begin
            wait (busy == 1'b1);
            wait (done == 1'b1);
            @(posedge clk);
        end
    endtask

    // PASS / FAIL helper
    task automatic check(
        input logic condition,
        input string pass_text,
        input string fail_text
    );
        begin
            if (condition) begin
                $display("PASS: %s", pass_text);
                pass_count = pass_count + 1;
            end
            else begin
                $display("FAIL: %s", fail_text);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // TEST 1: SPI modes 0,1,2,3 ------------------------------------------------------
    task automatic run_spi_mode(input logic [1:0] mode);
        begin
            spi_mode       = mode;
            transfer_width = 1'b1;
            clock_divider  = 16'd2;
            fake_mode      = 1'b0;
            early_cs_force = 1'b0;

            $display("");
            $display("==============================================");
            $display("SPI MODE %0d", mode);
            $display("==============================================");

            // Write 0x55 to DATA register.
            start_transaction(16'h0355);
            wait_transaction;

            check(
                data_reg == 8'h55,
                $sformatf("MODE %0d WRITE, DATA_REG = 0x%02h", mode, data_reg),
                $sformatf("MODE %0d WRITE, DATA_REG = 0x%02h, EXPECTED 0x55",
                          mode, data_reg)
            );

            check(
                (master_error == 1'b0) && (slave_error == 1'b0),
                $sformatf("MODE %0d WRITE ERROR CHECK", mode),
                $sformatf("MODE %0d WRITE ERROR, MASTER=%b SLAVE=%b",
                          mode, master_error, slave_error)
            );

            // Read DATA register.
            start_transaction(16'h8300);
            wait_transaction;

            check(
                rx_data == 16'h0055,
                $sformatf("MODE %0d READ, RX_DATA = 0x%04h", mode, rx_data),
                $sformatf("MODE %0d READ, RX_DATA = 0x%04h, EXPECTED 0x0055",
                          mode, rx_data)
            );

            check(
                (master_error == 1'b0) && (slave_error == 1'b0),
                $sformatf("MODE %0d READ ERROR CHECK", mode),
                $sformatf("MODE %0d READ ERROR, MASTER=%b SLAVE=%b",
                          mode, master_error, slave_error)
            );

            $display("COMPLETED SPI MODE %0d", mode);
        end
    endtask

    // TEST 2: 8-bit transfer ----------------------------------------------------------
    task automatic test_8bit;
        begin
            $display("");
            $display("==============================================");
            $display("8-BIT TRANSFER TEST");
            $display("==============================================");

            spi_mode       = 2'b00;
            transfer_width = 1'b0;
            clock_divider  = 16'd2;
            fake_mode      = 1'b1;
            early_cs_force = 1'b0;

            start_transaction(16'h005A);
            wait_transaction;

            check(
                rx_data == 16'h00A6,
                "8-BIT RX DATA = 0x00A6",
                $sformatf("8-BIT RX DATA = 0x%04h, EXPECTED 0x00A6", rx_data)
            );

            check(
                master_error == 1'b0,
                "8-BIT MASTER ERROR = 0",
                $sformatf("8-BIT MASTER ERROR = %b", master_error)
            );

            check(
                fake_bit_count == 8,
                "EXACTLY 8 SPI BITS TRANSFERRED",
                $sformatf("FAKE SLAVE COUNTED %0d BITS, EXPECTED 8",
                          fake_bit_count)
            );

            fake_mode = 1'b0;
        end
    endtask

    // TEST 3: Different clock divider values ----------------------------------------
    // SCLK period measurement for divider tests.
    
    integer rising_edges;
    time first_rising_edge;
    time second_rising_edge;
    time measured_period;

    always @(posedge sclk) begin
        if (!cs && fake_mode) begin
            rising_edges = rising_edges + 1;
            if (rising_edges == 1)
                first_rising_edge = $time;
            else if (rising_edges == 2) begin
                second_rising_edge = $time;
                measured_period = second_rising_edge - first_rising_edge;
            end
        end
    end

    task automatic test_divider(input logic [15:0] divider);
        begin
            $display("");
            $display("==============================================");
            $display("CLOCK DIVIDER = %0d", divider);
            $display("==============================================");

            clock_divider  = divider;
            transfer_width = 1'b0;
            spi_mode       = 2'b00;
            fake_mode      = 1'b1;
            early_cs_force = 1'b0;

            rising_edges = 0;
            first_rising_edge = 0;
            second_rising_edge = 0;
            measured_period = 0;

            start_transaction(16'h005A);
            wait_transaction;

            check(
                rx_data == 16'h00A6,
                $sformatf("DIVIDER %0d RX_DATA = 0x%04h", divider, rx_data),
                $sformatf("DIVIDER %0d RX_DATA = 0x%04h, EXPECTED 0x00A6", divider, rx_data)
            );

            check(
                master_error == 1'b0,
                $sformatf("DIVIDER %0d MASTER ERROR = 0", divider),
                $sformatf("DIVIDER %0d MASTER ERROR = %b", divider, master_error)
            );

            if (measured_period != 0)
                $display("MEASURED SCLK RISING-EDGE PERIOD = %0t ns", measured_period);
            else
                $display("WARNING: Could not measure SCLK period");

            fake_mode = 1'b0;
            @(posedge clk);
        end
    endtask

    // TEST 4: Back-to-back transactions -------------------------------------------
    task automatic test_back_to_back;
        begin
            $display("");
            $display("==============================================");
            $display("BACK-TO-BACK TRANSACTION TEST");
            $display("==============================================");

            spi_mode       = 2'b00;
            transfer_width = 1'b1;
            clock_divider  = 16'd2;
            fake_mode      = 1'b0;
            early_cs_force = 1'b0;

            // Transaction 1
            start_transaction(16'h0355);
            wait_transaction;

            check(data_reg == 8'h55,
                  "TRANSACTION 1 DATA_REG = 0x55",
                  $sformatf("TRANSACTION 1 DATA_REG = 0x%02h", data_reg));

            check(!master_error && !slave_error,
                  "TRANSACTION 1 ERROR CHECK",
                  "TRANSACTION 1 ERROR ASSERTED");

            // Transaction 2 immediately after transaction 1
            start_transaction(16'h03AA);
            wait_transaction;

            check(data_reg == 8'hAA,
                  "TRANSACTION 2 DATA_REG = 0xAA",
                  $sformatf("TRANSACTION 2 DATA_REG = 0x%02h", data_reg));

            check(!master_error && !slave_error,
                  "TRANSACTION 2 ERROR CHECK",
                  "TRANSACTION 2 ERROR ASSERTED");

            // Transaction 3 read
            start_transaction(16'h8300);
            wait_transaction;

            check(rx_data == 16'h00AA,
                  "TRANSACTION 3 RX_DATA = 0x00AA",
                  $sformatf("TRANSACTION 3 RX_DATA = 0x%04h", rx_data));

            check(!master_error && !slave_error,
                  "TRANSACTION 3 ERROR CHECK",
                  "TRANSACTION 3 ERROR ASSERTED");
        end
    endtask

    // TEST 5: Start while busy ------------------------------------------------------
    task automatic test_busy_start;
        logic [7:0] data_before;
        begin
            $display("");
            $display("==============================================");
            $display("START WHILE BUSY TEST");
            $display("==============================================");

            spi_mode       = 2'b00;
            transfer_width = 1'b1;
            clock_divider  = 16'd2;
            fake_mode      = 1'b0;
            early_cs_force = 1'b0;

            start_transaction(16'h0355);

            wait (busy == 1'b1);

            // Second start request while first transaction is active.
            @(negedge clk);
            tx_data = 16'h03AA;
            start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            start = 1'b0;

            wait (done == 1'b1);
            @(posedge clk);

            data_before = data_reg;

            check(
                data_before == 8'h55,
                "SECOND START WAS IGNORED WHILE BUSY",
                $sformatf("DATA_REG CHANGED TO 0x%02h", data_before)
            );

            check(
                master_error == 1'b0,
                "NO MASTER ERROR AFTER BUSY START REQUEST",
                "MASTER ERROR ASSERTED AFTER BUSY START"
            );

            check(
                data_reg == 8'h55,
                "FIRST TRANSACTION COMPLETED, DATA_REG = 0x55",
                $sformatf("DATA_REG = 0x%02h", data_reg)
            );
        end
    endtask

    // TEST 6: Correct CS timing -----------------------------------------------
    task automatic test_cs_timing;
        begin
            $display("");
            $display("==============================================");
            $display("CS TIMING TEST");
            $display("==============================================");

            spi_mode       = 2'b00;
            transfer_width = 1'b1;
            clock_divider  = 16'd2;
            fake_mode      = 1'b0;
            early_cs_force = 1'b0;

            start_transaction(16'h0355);

            wait (busy == 1'b1);

            check(
                cs == 1'b0,
                "CS ASSERTED LOW WHILE TRANSACTION IS ACTIVE",
                "CS WAS NOT ASSERTED LOW"
            );

            wait (done == 1'b1);
            @(posedge clk);

            check(
                cs == 1'b1,
                "CS DEASSERTED HIGH AFTER TRANSACTION",
                "CS REMAINED LOW AFTER TRANSACTION"
            );
        end
    endtask

    // TEST 7: Reset during transaction ------------------------------------------------
    task automatic test_reset_during_transaction;
        begin
            $display("");
            $display("==============================================");
            $display("RESET DURING TRANSACTION TEST");
            $display("==============================================");

            spi_mode       = 2'b00;
            transfer_width = 1'b1;
            clock_divider  = 16'd2;
            fake_mode      = 1'b0;
            early_cs_force = 1'b0;

            start_transaction(16'h03AA);
            wait (busy == 1'b1);

            check(
                busy == 1'b1,
                "TRANSACTION ACTIVE BEFORE RESET",
                "TRANSACTION DID NOT BECOME ACTIVE"
            );

            rst = 1'b1;
            @(posedge clk);
            #1;

            check(!busy,
                  "MASTER BUSY CLEARED BY RESET",
                  "MASTER BUSY REMAINED HIGH AFTER RESET");

            check(cs == 1'b1,
                  "CS DEASSERTED BY RESET",
                  "CS DID NOT RETURN HIGH");

            check(sclk == spi_mode[1],
                  "SCLK RETURNED TO IDLE LEVEL",
                  "SCLK DID NOT RETURN TO CPOL IDLE LEVEL");

            check(!done,
                  "DONE NOT ASSERTED BY RESET",
                  "DONE ASSERTED DURING RESET");

            check(!master_error && !slave_error,
                  "NO ERROR AFTER RESET",
                  "ERROR REMAINED ASSERTED AFTER RESET");

            rst = 1'b0;
            repeat (3) @(posedge clk);

            // Verify a new transaction works after reset.
            start_transaction(16'h03AA);
            wait_transaction;

            check(data_reg == 8'hAA,
                  "NEW TRANSACTION COMPLETED, DATA_REG = 0xAA",
                  $sformatf("DATA_REG = 0x%02h", data_reg));

            check(!master_error && !slave_error,
                  "NEW TRANSACTION COMPLETED WITHOUT ERROR",
                  "ERROR AFTER NEW TRANSACTION");
        end
    endtask

    // TEST 8: Invalid address -------------------------------------------------
    task automatic test_invalid_address;
        begin
            $display("");
            $display("==============================================");
            $display("INVALID ADDRESS TEST");
            $display("==============================================");

            spi_mode       = 2'b00;
            transfer_width = 1'b1;
            clock_divider  = 16'd2;
            fake_mode      = 1'b0;
            early_cs_force = 1'b0;

            // Establish known data.
            start_transaction(16'h0355);
            wait_transaction;

            check(data_reg == 8'h55,
                  "DATA REGISTER INITIALIZED TO 0x55",
                  $sformatf("DATA REGISTER = 0x%02h", data_reg));

            // 0x04 is outside the defined register map.
            start_transaction(16'h0499);
            wait_transaction;

            check(
                slave_error == 1'b1,
                "SLAVE ERROR ASSERTED FOR INVALID ADDRESS",
                "SLAVE ERROR WAS NOT ASSERTED"
            );

            check(
                data_reg == 8'h55,
                "DATA REGISTER UNCHANGED AFTER INVALID ADDRESS",
                $sformatf("DATA REGISTER CHANGED TO 0x%02h", data_reg)
            );

            check(
                control_reg == 8'h00,
                "CONTROL REGISTER UNCHANGED AFTER INVALID ADDRESS",
                $sformatf("CONTROL REGISTER CHANGED TO 0x%02h",
                          control_reg)
            );

            check(
                busy == 1'b0 && cs == 1'b1,
                "MASTER COMPLETED INVALID TRANSACTION",
                "MASTER DID NOT RETURN TO IDLE"
            );
        end
    endtask

    // TEST 9: CS deasserted early -------------------------------------------------
    task automatic test_early_cs;
        logic [7:0] data_before;
        begin
            $display("");
            $display("==============================================");
            $display("CS DEASSERTED EARLY TEST");
            $display("==============================================");

            spi_mode       = 2'b00;
            transfer_width = 1'b1;
            clock_divider  = 16'd2;
            fake_mode      = 1'b0;
            early_cs_force = 1'b0;

            start_transaction(16'h0355);
            wait_transaction;

            data_before = data_reg;

            check(data_reg == 8'h55,
                  "DATA REGISTER INITIALIZED TO 0x55",
                  $sformatf("DATA REGISTER = 0x%02h", data_reg));

            // Start a write, then externally release CS early.
            start_transaction(16'h03AA);
            wait (busy == 1'b1);

            repeat (5) @(posedge clk);

            early_cs_force = 1'b1;

            // Allow slave to observe CS rising.
            repeat (3) @(posedge clk);

            check(
                early_cs_force == 1'b1,
                "CS DEASSERTED EARLY",
                "CS EARLY-DEASSERT TEST DID NOT OCCUR"
            );

            check(
                slave_error == 1'b1,
                "SLAVE ERROR ASSERTED FOR EARLY CS",
                "SLAVE ERROR WAS NOT ASSERTED FOR EARLY CS"
            );

            check(
                data_reg == data_before,
                "DATA REGISTER UNCHANGED AFTER EARLY CS",
                $sformatf("DATA REGISTER CHANGED TO 0x%02h", data_reg)
            );

            // Reset is the clean recovery for this deliberately aborted Master transaction.
            rst = 1'b1;
            @(posedge clk);
            #1;
            rst = 1'b0;
            early_cs_force = 1'b0;
            repeat (3) @(posedge clk);

            check(
                !busy && cs,
                "MASTER RETURNED TO IDLE AFTER ABORT",
                "MASTER DID NOT RETURN TO IDLE AFTER ABORT"
            );
        end
    endtask

    // Generate one manual Mode-0 SPI clock.
    // Used for the incorrect-clock-count test.

    task automatic manual_spi_bit(input logic bit_value);
        begin
            @(negedge clk);
            count_mosi = bit_value;

            @(negedge clk);
            count_sclk = 1'b1;

            @(negedge clk);
            count_sclk = 1'b0;

            @(negedge clk);
        end
    endtask

    // TEST 10: Incorrect clock count -----------------------------------------------
    task automatic test_wrong_clock_count;
        integer i;
        logic [15:0] word;
        begin
            $display("");
            $display("==============================================");
            $display("INCORRECT CLOCK COUNT TEST");
            $display("==============================================");

            word = 16'h03AA;

            count_cs    = 1'b1;
            count_sclk  = 1'b0;
            count_mosi  = 1'b0;

            // Reset the corner-case slave.
            rst = 1'b1;
            repeat (3) @(posedge clk);
            rst = 1'b0;
            repeat (3) @(posedge clk);

            // Assert CS and send exactly 16 valid bits.
            @(negedge clk);
            count_cs = 1'b0;

            for (i = 15; i >= 0; i = i - 1)
                manual_spi_bit(word[i]);

            check(
                count_data_reg == 8'hAA,
                "16-BIT TRANSACTION WRITTEN, DATA_REG = 0xAA",
                $sformatf("DATA_REG = 0x%02h", count_data_reg)
            );

            // Deliberately send a 17th clock.
            manual_spi_bit(1'b0);

            @(negedge clk);
            count_cs = 1'b1;

            repeat (3) @(posedge clk);

            check(
                count_slave_error == 1'b1,
                "SLAVE ERROR ASSERTED FOR EXTRA CLOCK",
                "SLAVE ERROR WAS NOT ASSERTED FOR EXTRA CLOCK"
            );

            check(
                count_cs == 1'b1,
                "CS DEASSERTED AFTER TRANSACTION",
                "CS REMAINED ASSERTED"
            );
        end
    endtask

    // TEST 11: Random transactions with reference model ---------------------------------
    task automatic test_random_transactions;
        integer i;
        integer rw_random;
        integer addr_random;
        logic [7:0] write_data;
        logic [7:0] expected_data;
        logic [7:0] model_control;
        logic [7:0] model_data;
        logic [15:0] word;
        begin
            $display("");
            $display("==============================================");
            $display("RANDOM TRANSACTION TEST");
            $display("==============================================");

            spi_mode       = 2'b00;
            transfer_width = 1'b1;
            clock_divider  = 16'd2;
            fake_mode      = 1'b0;
            early_cs_force = 1'b0;

            model_control = control_reg;
            model_data    = data_reg;

            // Keep the same deterministic seed every simulation.

            for (i = 1; i <= 20; i = i + 1) begin

                rw_random   = $urandom_range(0,1);
                write_data  = $urandom_range(0,255);

                if (rw_random == 0) begin
                    // Writes are only legal to RW registers.
                    addr_random = ($urandom_range(0,1) == 0) ? 1 : 3;

                    word = {
                        1'b0,
                        addr_random[6:0],
                        write_data
                    };

                    start_transaction(word);
                    wait_transaction;
                    
                @(posedge clk);
                    if (addr_random == 1)
                        model_control = write_data;
                    else
                        model_data = write_data;

                    check(
                        (data_reg == model_data) &&
                        (control_reg == model_control) &&
                        !master_error &&
                        !slave_error,
                        $sformatf("TRANSACTION %0d WRITE ADDR=0x%02h DATA=0x%02h",
                                  i, addr_random, write_data),
                        $sformatf("TRANSACTION %0d WRITE FAILED: CONTROL=0x%02h EXPECTED=0x%02h DATA=0x%02h EXPECTED=0x%02h MASTER_ERR=%b SLAVE_ERR=%b",
                                  i, control_reg, model_control,
                                  data_reg, model_data,
                                  master_error, slave_error)
                    );
                end
                else begin
                    // Reads can target any defined register.
                    addr_random = $urandom_range(0,3);

                    word = {
                        1'b1,
                        addr_random[6:0],
                        8'h00
                    };

                    case (addr_random)
                        0: expected_data = 8'hA5;
                        1: expected_data = model_control;
                        2: expected_data = 8'h01;
                        3: expected_data = model_data;
                        default: expected_data = 8'h00;
                    endcase

                    start_transaction(word);
                    wait_transaction;

                    check(
                        (rx_data == {8'h00, expected_data}) &&
                        !master_error &&
                        !slave_error,
                        $sformatf("TRANSACTION %0d READ ADDR=0x%02h EXPECTED=0x%02h RX=0x%02h",
                                  i, addr_random, expected_data, rx_data[7:0]),
                        $sformatf("TRANSACTION %0d READ FAILED ADDR=0x%02h EXPECTED=0x%02h RX=0x%04h",
                                  i, addr_random, expected_data, rx_data)
                    );
                end
            end

            check(
                control_reg == model_control,
                "FINAL REFERENCE MODEL CONTROL REGISTER MATCH",
                $sformatf("CONTROL=0x%02h EXPECTED=0x%02h",
                          control_reg, model_control)
            );

            check(
                data_reg == model_data,
                "FINAL REFERENCE MODEL DATA REGISTER MATCH",
                $sformatf("DATA=0x%02h EXPECTED=0x%02h",
                          data_reg, model_data)
            );
        end
    endtask

    // TEST 12: MOSI / MISO data order -------------------------------------
    task automatic test_data_order;
        logic [15:0] captured_mosi;
        logic [15:0] expected_word;
        integer sample_count;
        begin
            $display("");
            $display("==============================================");
            $display("MOSI / MISO DATA ORDER TEST");
            $display("==============================================");

            spi_mode       = 2'b00;
            transfer_width = 1'b1;
            clock_divider  = 16'd2;
            fake_mode      = 1'b0;
            early_cs_force = 1'b0;

            captured_mosi = 16'h0000;
            expected_word = 16'h03A5;
            sample_count  = 0;

            // Capture exactly 16 MOSI bits on Mode-0 sample edges.
            // Using a fixed number of SCLK edges avoids a monitor race/hang at the CS transition.
           
            fork
                begin
                    repeat (16) begin
                        @(posedge sclk);
                        if (cs == 1'b0) begin
                            captured_mosi = {
                                captured_mosi[14:0], mosi
                            };
                            sample_count = sample_count + 1;
                        end
                    end
                end

                begin
                    start_transaction(expected_word);
                    wait_transaction;
                end
            join

            #1;

            $display("CAPTURED MOSI = 0x%04h", captured_mosi);

            check(
                (captured_mosi == expected_word) && (sample_count == 16),
                "MOSI DATA ORDER CORRECT",
                $sformatf("MOSI = 0x%04h EXPECTED 0x%04h, SAMPLES=%0d",
                          captured_mosi, expected_word, sample_count)
            );

            check(
                data_reg == 8'hA5,
                "MOSI STREAM PRODUCED CORRECT REGISTER WRITE",
                $sformatf("DATA REGISTER = 0x%02h", data_reg)
            );

            // Read back the same value to verify MISO ordering.
            start_transaction(16'h8300);
            wait_transaction;

            check(
                rx_data == 16'h00A5,
                "MISO DATA ORDER CORRECT",
                $sformatf("RX_DATA = 0x%04h EXPECTED 0x00A5", rx_data)
            );

            check(
                !master_error && !slave_error,
                "NO SPI DATA ORDER ERRORS",
                "SPI DATA ORDER ERROR ASSERTED"
            );
        end
    endtask

    // MAIN TEST

    initial begin

        rst            = 1'b1;
        start          = 1'b0;
        tx_data        = 16'h0000;
        transfer_width = 1'b1;
        spi_mode       = 2'b00;
        clock_divider  = 16'd2;

        fake_mode      = 1'b0;
        early_cs_force = 1'b0;

        count_sclk     = 1'b0;
        count_cs       = 1'b1;
        count_mosi     = 1'b0;

        pass_count = 0;
        fail_count = 0;

        // Initial reset.
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        $display("");
        $display("============================================================");
        $display(" FINAL SPI MASTER / SLAVE SELF-CHECKING TESTBENCH");
        $display("============================================================");

        // Required functional tests

        run_spi_mode(2'b00);
        run_spi_mode(2'b01);
        run_spi_mode(2'b10);
        run_spi_mode(2'b11);

        test_8bit;

        test_divider(16'd2);
        test_divider(16'd4);
        test_divider(16'd8);

        test_back_to_back;
        test_busy_start;
        test_cs_timing;
        test_reset_during_transaction;
        test_invalid_address;
        test_early_cs;
        test_wrong_clock_count;
        test_random_transactions;
        test_data_order;

        // Final summary

        $display("");
        $display("============================================================");
        $display(" FINAL SPI VERIFICATION SUMMARY");
        $display("============================================================");
        $display("TOTAL PASSES   = %0d", pass_count);
        $display("TOTAL FAILURES = %0d", fail_count);

        if (fail_count == 0) begin
            $display("");
            $display("============================================================");
            $display(" ALL MANDATORY SPI TESTS PASSED");
            $display("============================================================");
        end
        else begin
            $display("");
            $display("============================================================");
            $display(" SPI VERIFICATION FAILED");
            $display("============================================================");
        end

        #100;
        
        
        $finish;
    end

endmodule
