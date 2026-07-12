# Hardware Debugging Log

This document records the specific hardware flaws found in the original `inference_bram.v` implementation and the steps taken to isolate and fix them.

## Flaw 1: The Opcode/Pixel Clash (The "Random Timeout" Bug)
*   **Symptoms:** When processing images on the FPGA, the Python script would time out. The FPGA would randomly send back only a fraction of the expected 8,192 results (e.g., 2294 bytes, or 7981 bytes). 
*   **Root Cause:** In the `Rec_R` state, the FSM checked if the incoming byte was `OP_EXECUTE` (0xBB / 187). If an image naturally contained a pixel with a Red channel value of 187, the FPGA thought it was an opcode, aborted receiving the chunk, and started processing early.
*   **The Fix:** Redesigned the communication to use a **Length-Prefixed Protocol**. The host now tells the FPGA exactly how many pixels to expect (a 16-bit length counter). The FPGA counts down and blindly accepts data, completely ignoring opcodes while in the receiving state.

## Flaw 2: The Read-After-Write Hazard (The "Wrong Cluster" Bug)
*   **Symptoms:** In simulation (Phase 5 of our custom testbench), the very first pixel processed in a chunk would occasionally report the wrong cluster ID, even though the math cores were correct.
*   **Root Cause:** The pipeline transitioned directly from `PROC_STORE` (writing the last result to address N) into `TX_ISSUE` (reading the first result from address 0). If a write and read happen on the exact same clock edge, Block RAM exhibits "read-first" behavior, meaning the read outputs the *old, stale* data from the previous chunk.
*   **The Fix:** Introduced the `TX_SETTLE` state. This 1-clock-cycle buffer state ensures that the final write signal de-asserts and the data commits to the BRAM before any reading begins.

## Flaw 3: Single-Port BRAM Glitches
*   **Symptoms:** The original design failed synthesis timing checks and acted unpredictably on hardware.
*   **Root Cause:** The original `bram8bit.v` and `bram24bit.v` used a single address port with a combinational multiplexer (`addr = we ? wr_addr : rd_addr`). When FSM states changed, this mux would glitch, violating the strict setup-and-hold time requirements of the FPGA's physical Block RAM primitives.
*   **The Fix:** Rewrote the BRAM modules (`bram24bit_v2.v`) to use **True Dual-Port** interfaces, exposing a permanent, separate `wr_addr` and `rd_addr` to the FSM. This maps cleanly and glitch-free to the Tang Nano 9K's `DPB` (Dual-Port Block RAM) macro.

## Flaw 4: Unguarded `pixel_count` Buffer Overflows
*   **Symptoms:** If the host script sent an empty `OP_EXECUTE` without any pixels, the original FPGA design would hang forever in an infinite processing loop.
*   **Root Cause:** The `pixel_count` register was never explicitly reset to 0 at the start of a chunk. If it held a stale value, or if a chunk was empty, the FSM would blindly process uninitialized garbage data from memory.
*   **The Fix:** The FSM now explicitly clears `pixel_count` to 0 upon entering `IDLE` and receiving `OP_LOAD`. Furthermore, edge-case guards were added to return to `IDLE` immediately if a chunk length of 0 is requested.

## Debugging Workflow Today
1.  **Static Analysis:** Manually traced the clock-by-clock pipeline of the original FSM, identifying the read-after-write hazard and single-port mux issues.
2.  **RTL Rewrite:** Separated BRAM interactions into explicit 1-cycle pipeline stages. 
3.  **Simulation (`inference_bram_test.v`):** Built a self-checking Icarus Verilog testbench that simulated edge cases (partial chunks, empty executes). This caught Flaw #2 before we ever touched the hardware.
4.  **Synthesis Verification:** Used Yosys (`synth_gowin`) to verify that our new BRAMs successfully inferred exactly 16 `DPB` (True Dual-Port Block RAM) primitives, proving hardware readiness.
5.  **Hardware User Testing:** The user flashed the v2 bitstream, hit Flaw #1 (Opcode Clash) on real hardware, diagnosed the timeout symptom, and we collaboratively designed Protocol v3 to permanently resolve it.
