# Digital Communication Protocols

This project implements three common digital communication protocols—**UART, SPI, and I2C**—in Verilog. Each protocol includes its own RTL source files, testbench, and Makefile for simulation and verification.

The project provides practical examples for learning digital hardware design, serial communication, finite state machines (FSMs), and RTL verification.

<p align="center">
  <img src="1788916321768.gif" width="500" alt="Overview of UART, SPI, and I2C communication">
</p>

## Protocols

- **UART:** asynchronous serial transmission and reception with a baud generator and FIFOs.
- **SPI:** a Mode 0 SPI master supporting simultaneous transmission and reception.
- **I2C:** a master with 7-bit addressing, single-byte reads and writes, ACK/NACK handling, and clock stretching.

## Principles and Design

### UART

UART is an **asynchronous** serial interface that uses TX for transmission and RX for reception, without sharing a clock between devices. Both devices must agree on the baud rate and frame format. A start bit identifies the beginning of a frame, while a stop bit marks its end.

This implementation uses **8N1** framing: 8 data bits, no parity, and 1 stop bit. Data is transmitted least significant bit (LSB) first, and the line remains high while idle.

```text
UART frame: Idle(1) → Start(0) → D0 … D7 → Stop(1)

TX path: Data → TX FIFO → uart_tx → TXD
RX path: RXD → uart_rx → RX FIFO → Data
```

The `uart_top.v` module connects the transmitter, receiver, and two FIFOs. The `baud_gen.v` module generates timing ticks, while `uart_tx.v` controls transmission through an FSM. The `uart_rx.v` module synchronizes the input, samples at eight times the baud rate, and uses majority voting across three samples to determine each bit. The FIFOs buffer data so that external logic does not need to read or write in step with individual serial bits.

The testbench checks TX–RX loopback, multiple-byte transfers, and invalid stop-bit detection. The design demonstrates parallel-to-serial conversion and serial reception without a shared clock.

### SPI

SPI is a **synchronous** serial interface in which the master generates the SCK clock to control data exchange. MOSI carries data from the master to the slave, MISO carries data in the opposite direction, and CS selects the slave participating in the transaction. Separate data lines allow simultaneous transmission and reception.

CPOL and CPHA determine the idle clock level and sampling edge. This project implements **Mode 0 (`CPOL=0`, `CPHA=0`)**: SCK is low while idle, data is sampled on rising edges, and data changes on falling edges.

```text
Master ── SCK, MOSI, CS ──→ Slave
Master ←───── MISO ─────── Slave

FSM: IDLE → START → TRANSFER → STOP
```

The `master_spi.v` module uses a clock divider and two shift registers to exchange one byte, most significant bit (MSB) first. Upon a `start` request, the FSM selects the slave, generates SCK edges, and exchanges eight bits. At completion, it deasserts CS, updates the received byte, and generates a `done` pulse. The SCK frequency is determined by `f_sck = f_clk / (2 × CLK_DIV)`.

The testbench models a slave and checks data in both directions. The design focuses on coordinating clock edges, shift registers, and device selection.

### I2C

I2C is a **synchronous** serial interface with two shared bus lines: SCL for clock and SDA for data. Devices are selected by address, allowing multiple devices to share the bus. Both lines use **open-drain** signaling: devices either pull a line low or release it, while pull-up resistors bring it high.

A START condition occurs when SDA transitions from high to low while SCL is high; a STOP condition is the opposite transition. After each byte, the receiver responds on the ninth clock pulse with a low level for **ACK** or a high level for **NACK**. Clock stretching allows a slave to hold SCL low and make the master wait.

```text
Single-byte transaction:
START → 7-bit address + R/W → ACK → 8-bit data → ACK/NACK → STOP
```

The `i2c_master.v` module uses an FSM to generate START, send the address, read or write one byte, and finish with STOP. The controller waits for the actual SCL line to rise during clock stretching, retains NACK errors, and terminates early if the address is not acknowledged. For a single-byte read, the master sends NACK after receiving the byte to indicate completion.

The testbench uses pull-ups and an open-drain slave model to check data transfers, ACK/NACK handling, reset behavior, and clock stretching. The design demonstrates bidirectional bus control, releasing the data line for the other device, and handling transaction responses.

## Project Structure

```text
digital-communication-protocols/
├── UART/       # UART RTL and testbench
├── SPI/        # SPI master RTL and testbench
├── I2C/        # I2C master RTL and testbench
└── README.md
```

## Tools

- **Languages:** Verilog / SystemVerilog.
- **Simulation:** QuestaSim, ModelSim, or Icarus Verilog.
- **Automation:** Makefiles support compilation, simulation, and coverage reporting with a compatible simulator.
