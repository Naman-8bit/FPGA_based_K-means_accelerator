# --- Tang Nano 9K Modular Makefile ---

BOARD = tangnano9k
FAMILY = GW1N-9C
DEVICE = GW1NR-LV9QN88PC6/I5

# 1. Target Selection
# Defaults to the original 'inference' to not disturb your workflow.
# Override from terminal using: make TARGET=inference_bram
TARGET ?= inference

# Common constraint file
CST = constraints/tangnano9k.cst

# 2. Dynamic Source Routing based on the TARGET variable
ifeq ($(TARGET), inference)
    TOP = inference
    # Note: Paths updated to match your screenshot (functional_blocks folder)
    RTL_SRC = rtl/inference.v \
              rtl/functional_blocks/uart_rx.v \
              rtl/functional_blocks/uart_tx.v \
              rtl/functional_blocks/distance_unit.v \
              rtl/functional_blocks/comparator.v
else ifeq ($(TARGET), inference_bram)
    TOP = inference_bram
    RTL_SRC = rtl/inference_bram_test.v \
              rtl/functional_blocks/uart_rx.v \
              rtl/functional_blocks/uart_tx.v \
              rtl/functional_blocks/distance_unit.v \
              rtl/functional_blocks/comparator.v \
              rtl/functional_blocks/bram8bit.v \
              rtl/functional_blocks/bram24bit.v
endif

# 3. Dynamic Output Files (Prevents overwriting the other build)
JSON = build/$(TARGET)_synth.json
PNR = build/$(TARGET)_pnr.json
FS = build/$(TARGET)_bitstream.fs

# Default target
all: build_dir $(FS)

# Create build directory
build_dir:
	mkdir -p build

# Stage 1: Synthesis
$(JSON): $(RTL_SRC)
	yosys -p "read_verilog $(RTL_SRC); synth_gowin -top $(TOP) -json $(JSON)"

# Stage 2: Place and Route (Using himbaechel as requested)
$(PNR): $(JSON) $(CST)
	nextpnr-himbaechel --json $(JSON) --write $(PNR) --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST)

# Stage 3: Generate Bitstream
$(FS): $(PNR)
	gowin_pack -d $(FAMILY) -o $(FS) $(PNR)

# Stage 4: Flash to Board
flash: $(FS)
	openFPGALoader -b $(BOARD) $(FS)

# Cleanup
clean:
	rm -rf build/