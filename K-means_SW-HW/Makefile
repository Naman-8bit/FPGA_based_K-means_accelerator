# --- Tang Nano 9K Makefile ---

BOARD = tangnano9k
FAMILY = GW1N-9C
DEVICE = GW1NR-LV9QN88PC6/I5

# 1. Define your files
RTL_SRC = 
CST = constraints/tangnano9k.cst

# Output files
JSON = build/synth.json
PNR = build/pnr.json
FS = build/bitstream.fs

# Default target
all: build_dir $(FS)

# Create build directory
build_dir:
	mkdir -p build

# Stage 1: Synthesis
$(JSON): $(RTL_SRC)
	yosys -p "read_verilog $(RTL_SRC); synth_gowin -top blinky -json $(JSON)"

# Stage 2: Place and Route (UPDATED FOR HIMBAECHEL)
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