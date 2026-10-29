"""R12 pre-registered surface in model-space meters; no runtime integration."""
import math

SHAPE = {7.4: (0.25, 0.12), 11.8: (0.40, 0.17), 6.8: (0.54, 0.09)}

def coefficients(width):
    if width not in SHAPE:
        raise ValueError('unknown R12 sail width')
    return SHAPE[width]

def breadth(v, width):
    k, _ = coefficients(width)
    return width * (1 + 0.10 * math.sin(math.pi * v) - k * v * v)

def rake(width):
    return coefficients(width)[1]

def surface(u, v, height, width, base):
    b = breadth(v, width)
    z = b * (u - 0.70) - 0.045 * width * v * v
    y = base + height * v + height * rake(width) * (1-u) * v**2.2
    x = 0.32 + (0.30 * math.sin(math.pi*v) + 0.025 * math.sin(math.pi * ((8*v) % 1))**2) * math.sin(math.pi*u)
    return x, y, z
