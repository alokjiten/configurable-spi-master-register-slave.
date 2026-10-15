# Configurable SPI Master with Register-Based SPI Slave

## 1. Project Overview

This project implements a configurable SPI Master, a register-based SPI Slave, and a self-checking SystemVerilog testbench using Vivado.

The SPI Master supports SPI Modes 0, 1, 2, and 3, configurable clock division, 8-bit and 16-bit transfers, full-duplex MOSI/MISO communication, start/busy/done control, chip-select control, and error indication.

The SPI Slave implements a memory-mapped register interface over SPI, supporting read-only and read/write registers, address decoding, and error detection.

## 2. Key Features

- SPI Modes 0–3 with configurable CPOL and CPHA
- Programmable SPI clock divider
- 8-bit and 16-bit transfer widths
- Full-duplex serial communication
- FSM-based SPI Master control
- Register-based SPI Slave
- Read/write register operations
- Start, busy, done, and chip-select control
- Master and Slave error indication
- Self-checking SystemVerilog testbench
- Vivado synthesis, timing, and resource utilization analysis

## 3. System Architecture

The design consists of three main RTL modules:

- `spi_master.sv` — generates SCLK, transmits MOSI data, samples MISO, and controls transfers.
- `spi_slave.sv` — receives commands, decodes register addresses, handles register access, and returns data through MISO.
- `spi_top.sv` — connects the Master and Slave through SCLK, MOSI, MISO, and CS.

The testbench, `tb_spi_master_slave.sv`, verifies normal transactions and selected error conditions.

![SPI System Architecture](05_Architecture_and_FSM/architecture_diagram.png)

## 4. SPI Modes

| SPI Mode | CPOL | CPHA | Clock Idle | Sampling Edge |
|---|---:|---:|---|---|
| Mode 0 | 0 | 0 | Low | Rising |
| Mode 1 | 0 | 1 | Low | Falling |
| Mode 2 | 1 | 0 | High | Falling |
| Mode 3 | 1 | 1 | High | Rising |

The SPI mode is selected through `spi_mode[1:0]`.

## 5. Clock Divider

The SPI clock is generated from the system clock using the configurable `clock_divider` input.

The expected nominal relationship is:

\[
f_{\text{SCLK}} \approx \frac{f_{\text{clk}}}{2 \times \text{clock\_divider}}
\]

The testbench exercises divider values of 2, 4, and 8 to check the effect on the SPI clock period.

## 6. Transfer Width

The Master supports two transfer widths:

- `transfer_width = 0`: 8-bit transfer
- `transfer_width = 1`: 16-bit transfer

The register-based SPI protocol uses 16-bit transactions.

## 7. SPI Transaction Format

Each register transaction is 16 bits wide.

| Bit Field | Description |
|---|---|
| Bit 15 | Read/write flag: `0` = write, `1` = read |
| Bits 14:8 | Register address |
| Bits 7:0 | Write data or dummy data for a read |

### Write Example

`16'h0355`

- Read/write flag: `0`
- Register address: `0x03`
- Data: `0x55`

This writes `0x55` to the Data register at address `0x03`.

### Read Example

`16'h8300`

- Read/write flag: `1`
- Register address: `0x03`
- Dummy byte: `0x00`

The Slave returns the Data register value through MISO.

## 8. SPI Slave Register Map

| Address | Register | Access | Description |
|---|---|---|---|
| `0x00` | Device ID | RO | Fixed device identification value `0xA5` |
| `0x01` | Control | RW | Control register |
| `0x02` | Status | RO | Status register, initialized to `0x01` |
| `0x03` | Data | RW | Data register |

RO means read-only; RW means read/write.

## 9. SPI Master Control FSM

The Master uses five control states:

`IDLE → LOAD → TRANSFER → FINISH_TRANSFER → FINISH → IDLE`

![SPI Master FSM](05_Architecture_and_FSM/master_fsm_diagram.png)

- **IDLE:** Waits for a start request.
- **LOAD:** Loads transmit data and configures the transfer.
- **TRANSFER:** Generates SCLK, transmits MOSI data, and samples MISO.
- **FINISH_TRANSFER:** Completes the final bit and prepares the received data.
- **FINISH:** Generates the completion indication, clears busy, and returns to idle.

A start request received while the Master is busy is intended to be ignored.

## 10. Verification

The self-checking testbench is located in:

`02_Testbench/tb_spi_master_slave.sv`

The supplied test scenarios cover:

- SPI Modes 0, 1, 2, and 3
- 8-bit transfers
- Clock divider values 2, 4, and 8
- Back-to-back transactions
- Start request while busy
- Chip-select timing
- Reset during a transaction
- Invalid register addresses
- Early chip-select deassertion
- Incorrect SPI clock count
- Randomized transactions with a reference model
- MOSI/MISO data ordering

## 11. Reported Simulation Results

According to the supplied project notes:

| Metric | Result |
|---|---:|
| Total passes | 83 |
| Total failures | 0 |
| Reported final status | ALL MANDATORY SPI TESTS PASSED |

These are the reported results from the supplied testbench run. They should be reproduced by rerunning the simulation before being described as independently verified.

## 12. FPGA Resource Utilization

The supplied Vivado utilization screenshot reports:

| Resource | Reported Usage |
|---|---:|
| Slice LUTs | 108 |
| Slice Registers | 125 |
| Bonded I/O | 86 |
| BUFGCTRL | 1 |

![Vivado Resource Utilization](04_Waveforms/Utilization_Report.png)

## 13. Timing Analysis

The supplied Vivado timing summary reports:

| Timing Metric | Reported Value |
|---|---:|
| Worst Negative Slack (WNS) | +5.485 ns |
| Total Negative Slack (TNS) | 0.000 ns |
| Setup failing endpoints | 0 |
| Worst Hold Slack (WHS) | +0.132 ns |
| Total Hold Slack (THS) | 0.000 ns |
| Hold failing endpoints | 0 |
| Worst Pulse Width Slack | +4.500 ns |

The report indicates that all user-specified timing constraints were met for the implementation shown.

![Vivado Timing Summary](04_Waveforms/Timing_Summary.png)

![Vivado Implementation View](04_Waveforms/Implementation_View.png)

Resource utilization and timing results depend on the target FPGA, timing constraints, tool version, and implementation settings.

## 14. Waveform Verification

The supplied waveforms illustrate SPI activity and control signals for the four operating modes.

### SPI Mode 0

![SPI Mode 0](04_Waveforms/SPI_Mode_0.png)

### SPI Mode 1

![SPI Mode 1](04_Waveforms/SPI_Mode_1.png)

### SPI Mode 2

![SPI Mode 2](04_Waveforms/SPI_Mode_2.png)

### SPI Mode 3

![SPI Mode 3](04_Waveforms/SPI_Mode_3.png)

Signals include `clk`, `rst`, `start`, `tx_data`, `transfer_width`, `spi_mode`, `clock_divider`, `rx_data`, `busy`, `done`, `sclk`, `mosi`, `miso`, `cs`, `master_error`, and `slave_error`.

## 15. Corner Cases

- **Start while busy:** Applies a second start request during an active transaction.
- **Reset during transaction:** Checks reset behavior and return to idle.
- **Invalid address:** Exercises the Slave's error indication for an undefined address.
- **Early CS deassertion:** Tests detection of an incomplete transaction.
- **Incorrect clock count:** Exercises the Slave's error reporting for an incorrect number of SPI clocks.

## 16. Limitations

- Transfer width is limited to 8 or 16 bits.
- The register transaction format is fixed at 16 bits.
- Four register addresses are defined.
- Error indication is implemented, but a dedicated timeout counter is not.
- TX/RX FIFOs are not implemented.
- No external physical SPI peripheral is claimed.

## 17. Repository Structure

```text
.
├── 01_RTL/
│   ├── spi_master.sv
│   ├── spi_slave.sv
│   └── spi_top.sv
├── 02_Testbench/
│   └── tb_spi_master_slave.sv
## 18. Tools and Technologies

- SystemVerilog
- Xilinx Vivado
- Vivado Simulator (XSim)
- RTL simulation and waveform analysis
- FPGA synthesis and implementation reports

## Author

Alok Jiten Rao
