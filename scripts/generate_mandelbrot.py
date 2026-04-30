import math

def mandelbrot(c, max_iter):
    z = 0
    for i in range(max_iter):
        if abs(z) > 2:
            return i
        z = z*z + c
    return max_iter

def generate_mandelbrot(width, height, max_iter):
    # Characters to use for density
    chars = " .:-=+*#%@"
    
    # Adjust range to center and zoom correctly
    x_start, x_end = -2.0, 0.5
    y_start, y_end = -1.2, 1.2
    
    # Aspect ratio correction (terminal characters are usually ~2:1 height:width)
    y_range = y_end - y_start
    x_range = x_end - x_start
    
    output = []
    for y in range(height):
        line = ""
        for x in range(width):
            real = x_start + (x / width) * x_range
            imag = y_start + (y / height) * y_range
            c = complex(real, imag)
            m = mandelbrot(c, max_iter)
            
            # Map iteration count to character
            char_idx = int((m / max_iter) * (len(chars) - 1))
            line += chars[char_idx]
        output.append(line)
    return "\n".join(output)

if __name__ == "__main__":
    # fastfetch logo usually takes about 40-60 width and 20-30 height
    width = 40
    height = 20
    max_iter = 30
    
    mandelbrot_ascii = generate_mandelbrot(width, height, max_iter)
    print(mandelbrot_ascii)