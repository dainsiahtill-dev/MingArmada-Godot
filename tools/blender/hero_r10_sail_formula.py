"""R10 shoulder candidate in the existing Godot-metre authoring basis."""
import math


def breadth(v, width, coefficient):
    return width * (1 + .10 * math.sin(math.pi * v) - .40 * v ** 2
                    + coefficient * math.sin(math.pi * v) ** 2 * (1 - 2 * v))


def surface(u, v, height, width, base, coefficient, panel_amplitude=.025):
    span = breadth(v, width, coefficient)
    z = span * (u - .70) - width * .045 * v * v
    y = base + height * v + height * .15 * (1 - u) * v ** 2.2
    panel = math.sin(math.pi * ((v * 8) % 1)) ** 2
    x = .32 + (.30 * math.sin(math.pi * v) + panel_amplitude * panel) * math.sin(math.pi * u)
    return x, y, z


def inverse_uv(y, z, height, width, base, coefficient):
    v = max(0., min(1., (y - base) / (height * 1.12)))
    for _ in range(12):
        span = breadth(v, width, coefficient)
        u = max(0., min(1., (z + width * .045 * v * v) / span + .70))
        v = max(0., min(1., (y - base) / height - .15 * (1 - u) * v ** 2.2))
    return u, v
