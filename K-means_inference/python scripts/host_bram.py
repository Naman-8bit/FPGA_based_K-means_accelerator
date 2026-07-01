import serial
import numpy as np
import cv2
import time

# --- CONFIGURATION ---
SERIAL_PORT = '/dev/ttyUSB0' # Check your actual port (e.g., /dev/ttyACM0 or COM3 on Windows)
BAUD_RATE   = 57600
CHUNK_SIZE  = 8192           # Perfectly matches your FPGA BRAM!
OP_LOAD     = b'\xAA'
OP_EXECUTE  = b'\xBB'

def main():
    print("Opening serial port...")
    # timeout=None forces Python to block and wait for the FPGA to finish computing
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=5)
    except Exception as e:
        print(f"Failed to open port {SERIAL_PORT}: {e}")
        return
    # Change timeout=None to timeout=5. 
    # If the FPGA crashes, Python will now gracefully exit after 5 seconds instead of hanging forever.
        
    # 1. Load and prepare the image
    image_path = 'data/test.jpg' # Put a small image in the same folder!
    img = cv2.imread(image_path)
    if img is None:
        print(f"Error: Could not load {image_path}. Make sure it exists.")
        return
        
    # Convert BGR (OpenCV default) to RGB
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    height, width, channels = img.shape
    
    # Flatten the image into a 1D array of pixels (R, G, B)
    flat_pixels = img.reshape(-1, 3)
    total_pixels = len(flat_pixels)
    print(f"Image loaded: {width}x{height} ({total_pixels} pixels)")

    # Array to hold the incoming cluster IDs from the FPGA
    result_clusters = np.zeros(total_pixels, dtype=np.uint8)
    
    print("\n--- STARTING HARDWARE ACCELERATION ---")
    start_time = time.time()
    
    # 2. Process in chunks
    for i in range(0, total_pixels, CHUNK_SIZE):
        chunk = flat_pixels[i : i + CHUNK_SIZE]
        valid_pixels = len(chunk)
        
        # --- THE FIX: PAD PARTIAL CHUNKS ---
        # If this is the last chunk and it's smaller than 8192, fill it with zeros
        if valid_pixels < CHUNK_SIZE:
            pad_size = CHUNK_SIZE - valid_pixels
            padding = np.zeros((pad_size, 3), dtype=np.uint8)
            chunk = np.vstack((chunk, padding))
            
        print(f"Sending chunk {i//CHUNK_SIZE + 1} ({valid_pixels} real pixels, padded to {CHUNK_SIZE})...")
        
        # Wake up the FPGA FSM
        ser.write(OP_LOAD)
        
        # Send the exact 24KB block safely
        byte_data = chunk.tobytes()
        for b_idx in range(0, len(byte_data), 1024):
            ser.write(byte_data[b_idx : b_idx+1024])
            ser.flush()
            
        # 3. Wait for the FPGA to compute and send results back
        # The FPGA will ALWAYS send back exactly CHUNK_SIZE results now
        result_bytes = ser.read(CHUNK_SIZE)
        
        if len(result_bytes) < CHUNK_SIZE:
            print(f"\n[ERROR] Hardware timeout! Expected {CHUNK_SIZE} bytes, got {len(result_bytes)}.")
            return
            
        # Store ONLY the valid results (ignore the padded dummy results)
        result_clusters[i : i + valid_pixels] = list(result_bytes)[:valid_pixels]
        
    end_time = time.time()
    print(f"\n--- INFERENCE COMPLETE ---")
    print(f"Hardware processing time: {end_time - start_time:.2f} seconds")

    # 4. Reconstruct the image (Color-coding the clusters)
    # We map Cluster 0 -> Red, Cluster 1 -> Green, Cluster 2 -> Blue
    colors = np.array([
        [255, 0, 0],   # Cluster 0: Red
        [0, 255, 0],   # Cluster 1: Green
        [0, 0, 255]    # Cluster 2: Blue
    ], dtype=np.uint8)
    
    # Apply the colors to the cluster IDs
    segmented_flat = colors[result_clusters]
    segmented_img = segmented_flat.reshape(height, width, 3)
    
    # Convert back to BGR for saving
    segmented_img_bgr = cv2.cvtColor(segmented_img, cv2.COLOR_RGB2BGR)
    cv2.imwrite('data/segmented_output.jpg', segmented_img_bgr)
    print("Saved FPGA output to segmented_output.jpg")
    
    ser.close()
    # temporary debug — read one extra byte which might be a status
    ser.timeout = 0.1
    debug_byte = ser.read(1)
    print(f"  First result byte: {list(debug_byte)}")
    ser.timeout = 5


if __name__ == '__main__':
    main()