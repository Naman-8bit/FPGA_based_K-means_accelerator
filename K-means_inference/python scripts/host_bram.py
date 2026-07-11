import serial
import numpy as np
import cv2
import time
import struct

# --- CONFIGURATION ---
SERIAL_PORT = '/dev/ttyUSB1'
BAUD_RATE   = 115200
CHUNK_SIZE  = 8192
OP_LOAD     = b'\xAA'

def main():
    print(f"Opening serial port {SERIAL_PORT} at {BAUD_RATE} baud...")
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=5)
    except Exception as e:
        print(f"Failed to open port {SERIAL_PORT}: {e}")
        return
        
    time.sleep(0.5)
        
    image_path = '../data/test.jpg'
    img = cv2.imread(image_path)
    if img is None:
        print(f"Error: Could not load {image_path}. Make sure it exists.")
        return
        
    img = cv2.resize(img, (400, 400))
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    height, width, channels = img.shape
    
    flat_pixels = img.reshape(-1, 3)
    total_pixels = len(flat_pixels)
    print(f"Image loaded: {width}x{height} ({total_pixels} pixels)")

    result_clusters = np.zeros(total_pixels, dtype=np.uint8)
    
    print("\n--- STARTING HARDWARE ACCELERATION (v3 PROTOCOL) ---")
    start_time = time.time()
    
    for i in range(0, total_pixels, CHUNK_SIZE):
        chunk = flat_pixels[i : i + CHUNK_SIZE]
        valid_pixels = len(chunk)
            
        print(f"Sending chunk {i//CHUNK_SIZE + 1} ({valid_pixels} pixels)...")
        
        # 1. Send OP_LOAD
        ser.write(OP_LOAD)
        
        # 2. Send Length (High Byte, Low Byte)
        # using struct pack for big-endian unsigned short (16 bits)
        length_bytes = struct.pack('>H', valid_pixels)
        ser.write(length_bytes)
        
        # 3. Send actual pixels
        byte_data = chunk.tobytes()
        ser.write(byte_data)
        ser.flush()
        
        # 4. Wait for exactly valid_pixels results
        result_bytes = ser.read(valid_pixels)
        
        if len(result_bytes) < valid_pixels:
            print(f"\n[ERROR] Hardware timeout! Expected {valid_pixels} bytes, got {len(result_bytes)}.")
            return
            
        result_clusters[i : i + valid_pixels] = list(result_bytes)
        
    end_time = time.time()
    print(f"\n--- INFERENCE COMPLETE ---")
    print(f"Hardware processing time: {end_time - start_time:.2f} seconds")

    colors = np.array([
        [255, 0, 0],
        [0, 255, 0],
        [0, 0, 255]
    ], dtype=np.uint8)
    
    segmented_flat = colors[result_clusters]
    segmented_img = segmented_flat.reshape(height, width, 3)
    
    segmented_img_bgr = cv2.cvtColor(segmented_img, cv2.COLOR_RGB2BGR)
    cv2.imwrite('../data/segmented_output_bram_v2.jpg', segmented_img_bgr)
    print("Saved FPGA output to data/segmented_output_bram_v2.jpg")
    
    ser.close()

if __name__ == '__main__':
    main()
