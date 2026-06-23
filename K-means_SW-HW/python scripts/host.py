import serial
import time
from PIL import Image

# --- CONFIGURATION ---
SERIAL_PORT = '/dev/ttyUSB1'  # Update if yours is ttyUSB0 or COM3
BAUD_RATE = 115200

# These match the exact hardcoded centroids in your Verilog 'inference.v'
CENTROID_COLORS = {
    0: (255, 0, 0),   # Cluster 0: Pure Red
    1: (0, 255, 0),   # Cluster 1: Pure Green
    2: (0, 0, 255)    # Cluster 2: Pure Blue
}

def process_image(input_path, output_path):
    print(f"Opening {input_path}...")
    
    # Open image and resize to 100x100 for a fast first test
    original_img = Image.open(input_path).convert('RGB')
    img = original_img.resize((400, 400))
    width, height = img.size
    
    # Create a blank canvas to draw the FPGA's output
    out_img = Image.new('RGB', (width, height))
    pixels_out = out_img.load()

    print(f"Connecting to FPGA on {SERIAL_PORT}...")
    try:
        with serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2) as ser:
            time.sleep(1) # Give the serial port a second to settle
            
            total_pixels = width * height
            print(f"Streaming {total_pixels} pixels to the hardware...")
            
            start_time = time.time()
            
            for y in range(height):
                for x in range(width):
                    # Grab R, G, B from the current pixel
                    r, g, b = img.getpixel((x, y))
                    
                    # 1. Fire the data point into the FPGA!
                    ser.write(bytes([r, g, b]))
                    
                    # 2. Wait for the Math Core to reply
                    response = ser.read(1)
                    
                    if len(response) == 0:
                        print(f"\n[ERROR] FPGA timed out at pixel ({x}, {y})!")
                        return
                        
                    # Mask out the bottom 2 bits to get the raw cluster ID
                    cluster_id = response[0] & 0x03 
                    
                    # 3. Paint the new pixel using the centroid color
                    pixels_out[x, y] = CENTROID_COLORS.get(cluster_id, (0, 0, 0))
                    
                # Simple progress tracker
                if (y + 1) % 10 == 0:
                    print(f"Row {y + 1}/{height} complete...")
                    
            end_time = time.time()
            print(f"Hardware Inference Complete! Took {end_time - start_time:.2f} seconds.")
            
            # Save and display the final AI-clustered image
            out_img.save(output_path)
            print(f"Saved to {output_path}")
            
    except Exception as e:
        print(f"Connection Error: {e}")

if __name__ == "__main__":
    # Point to the data directory!
    process_image("../data/test.jpg", "../data/fpga_output.jpg")