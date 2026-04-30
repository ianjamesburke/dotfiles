import os
import math
import random
import argparse
import sys
import time
import tty
import termios
import shutil
import subprocess

def getch():
    """Reads a single character from stdin without requiring a return."""
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(sys.stdin.fileno())
        ch = sys.stdin.read(1)
        if ch == '\x1b':  # Handle arrow keys (escape sequences)
            seq = sys.stdin.read(2)
            if seq == '[A': return 'up'
            if seq == '[B': return 'down'
            if seq == '[C': return 'right'
            if seq == '[D': return 'left'
            return ch  # escape key itself if no sequence
        return ch
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

# hey babyy boiiii

def copy_to_clipboard(text):
    """Tries to copy text to clipboard using wl-copy or xclip."""
    try:
        # Try wl-copy first (Wayland)
        p = subprocess.Popen(['wl-copy'], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p.communicate(input=text.encode('utf-8'))
        if p.returncode == 0: return True
    except FileNotFoundError:
        pass

    try:
        # Try xclip (X11)
        p = subprocess.Popen(['xclip', '-selection', 'clipboard'], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p.communicate(input=text.encode('utf-8'))
        if p.returncode == 0: return True
    except FileNotFoundError:
        pass

    return False

def mandelbrot(c, max_iter):
    z = 0
    for i in range(max_iter):
        if abs(z) > 2:
            return i
        z = z*z + c
    return max_iter

def generate_mandelbrot(width, height, max_iter, x_center, y_center, zoom):
    # Characters to use for density
    chars = " .:-=+*#%@"
    
    # Calculate visible range based on center and zoom
    # Base scale: 3.0 units wide (-2 to 1) at zoom 1.0
    x_range = 3.0 / zoom
    y_range = 3.0 / zoom * (height / width) * 2.2 # Aspect ratio correction for typical terminal fonts (~2:1)
    
    x_start = x_center - x_range / 2
    y_start = y_center - y_range / 2
    
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

def find_interesting_point(max_iter):
    """
    Tries to find a point on the boundary of the Mandelbrot set.
    """
    attempts = 0
    while attempts < 1000:
        r = random.uniform(-2.0, 0.5)
        i = random.uniform(-1.2, 1.2)
        c = complex(r, i)
        m = mandelbrot(c, max_iter)
        if 10 < m < max_iter:
            return r, i
        attempts += 1
    return -0.7436438870371587, 0.1318259042053119

def interactive_mode(width, height, max_iter, x, y, zoom):
    msg = ""
    while True:
        # Generate frame
        frame = generate_mandelbrot(width, height, max_iter, x, y, zoom)
        
        # UI Overlay
        ui = f"\n[EXPLORE] x:{x:.6f} y:{y:.6f} zoom:{zoom:.2f} iter:{max_iter}"
        controls = "Controls: Arrows(move) i/o(zoom) +/- (detail) s(save cmd) q(quit)"
        
        sys.stdout.write("\033[H" + frame + "\033[K\n") # Home + Frame + Clear line
        sys.stdout.write(f"\033[K{ui}\n\033[K{controls}\n\033[K{msg}")
        sys.stdout.write("\033[J") # Clear rest of screen
        sys.stdout.flush()
        
        msg = "" # Reset message
        key = getch()
        
        # Calculate movement step (move 10% of the screen width)
        move_step = (3.0 / zoom) * 0.1
        
        if key == 'q':
            break
        elif key == 'up':
            y -= move_step
        elif key == 'down':
            y += move_step
        elif key == 'left':
            x -= move_step
        elif key == 'right':
            x += move_step
        elif key == 'i':
            zoom *= 1.25
        elif key == 'o':
            zoom /= 1.25
        elif key == '+' or key == '=':
            max_iter += 50
        elif key == '-' or key == '_':
            max_iter = max(50, max_iter - 50)
        elif key == 's':
            cmd = f"python3 scripts/mandelbrot.py --animate --x {x} --y {y} --zoom {zoom} --iter {max_iter} --frames 100"
            if copy_to_clipboard(cmd):
                msg = f"\033[32mCommand copied to clipboard!\033[0m"
            else:
                msg = f"\033[33mClipboard failed. Command:\n{cmd}\033[0m"

def main():
    parser = argparse.ArgumentParser(description="Generate an ASCII Mandelbrot set.")
    parser.add_argument("--random", action="store_true", help="Start at a random interesting location.")
    parser.add_argument("--animate", action="store_true", help="Run a zoom animation.")
    parser.add_argument("--explore", action="store_true", help="Interactive exploration mode.")
    parser.add_argument("--frames", type=int, default=50, help="Number of frames for animation.")
    parser.add_argument("--x", type=float, default=-0.75, help="Center X coordinate.")
    parser.add_argument("--y", type=float, default=0.0, help="Center Y coordinate.")
    parser.add_argument("--zoom", type=float, default=1.0, help="Zoom level.")
    parser.add_argument("--width", type=int, help="Output width.")
    parser.add_argument("--height", type=int, help="Output height.")
    parser.add_argument("--iter", type=int, default=100, help="Max iterations.")
    
    args = parser.parse_args()
    
    try:
        term_w, term_h = os.get_terminal_size()
    except OSError:
        term_w, term_h = 80, 24
        
    width = args.width if args.width else term_w
    # Leave room for UI in explore mode
    height_offset = 4 if args.explore else 1
    height = args.height if args.height else (term_h - height_offset)
    
    x_c, y_c, zoom = args.x, args.y, args.zoom
    
    if args.random or ((args.animate or args.explore) and args.x == -0.75 and args.y == 0.0):
        x_c, y_c = find_interesting_point(args.iter)

    if args.explore:
        try:
            interactive_mode(width, height, args.iter, x_c, y_c, zoom)
        except KeyboardInterrupt:
            print("\nExploration stopped.")
            
    elif args.animate:
        # Animation parameters
        start_zoom = 1.0
        target_zoom = args.zoom if args.zoom > 1.0 else 100.0 # Default if target is weird
        
        start_iter = 50
        target_iter = args.iter
        
        # Calculate per-frame multipliers/steps
        # Formula: start * (factor ^ frames) = target  ->  factor = (target/start)^(1/frames)
        zoom_factor = (target_zoom / start_zoom) ** (1 / args.frames)
        
        try:
            # Hide cursor
            sys.stdout.write("\033[?25l")
            
            for f in range(args.frames):
                # Calculate current state
                current_zoom = start_zoom * (zoom_factor ** f)
                
                # Linear interpolation for iterations
                progress = f / args.frames
                current_iter = int(start_iter + (target_iter - start_iter) * progress)
                
                frame = generate_mandelbrot(width, height, current_iter, x_c, y_c, current_zoom)
                
                sys.stdout.write("\033[H" + frame + "\n")
                sys.stdout.write(f"Frame: {f+1}/{args.frames} | Zoom: {current_zoom:.2f} | Iter: {current_iter} | x: {x_c:.5f}, y: {y_c:.5f}\033[K")
                sys.stdout.flush()
                
                time.sleep(0.05)
                
            # Ensure we show the final frame exactly as requested
            frame = generate_mandelbrot(width, height, target_iter, x_c, y_c, target_zoom)
            sys.stdout.write("\033[H" + frame + "\n")
            sys.stdout.write(f"Frame: {args.frames}/{args.frames} | Zoom: {target_zoom:.2f} | Iter: {target_iter} | x: {x_c:.5f}, y: {y_c:.5f} [DONE]\033[K")
            sys.stdout.flush()
            
        except KeyboardInterrupt:
            pass
        finally:
            # Show cursor
            sys.stdout.write("\033[?25h\n")
            
    else:
        if args.random:
            print(f"Location: x={x_c:.5f}, y={y_c:.5f}, zoom={zoom:.2f}", file=sys.stderr)
        print(generate_mandelbrot(width, height, args.iter, x_c, y_c, zoom))

if __name__ == "__main__":
    main()
