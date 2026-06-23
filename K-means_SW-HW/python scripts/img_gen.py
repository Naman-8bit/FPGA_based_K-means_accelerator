from PIL import Image

# Let's generate a 400x400 high-res test image
width, height = 400, 400
img = Image.new('RGB', (width, height))
pixels = img.load()

for y in range(height):
    for x in range(width):
        # Create a smooth gradient across the axes
        # Red increases left to right
        r = int((x / width) * 255)
        # Green increases top to bottom
        g = int((y / height) * 255)
        # Blue is strongest in the top-left corner
        b = int(((width - x) / width) * 255)
        
        pixels[x, y] = (r, g, b)

img.save("../data/test.jpg")
print(f"Generated an amazing {width}x{width} test pattern as 'test.jpg'!")