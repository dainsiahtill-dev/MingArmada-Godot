"""R15 pre-registered candidate sail surface in metres, not production logic."""
import math
SHAPE={7.2:(.18,.10),12.2:(.30,.17),6.2:(.50,.08)}
def coefficients(width):
    if width not in SHAPE:raise ValueError('unknown R15 sail width')
    return SHAPE[width]
def breadth(v,width):
    k,_=coefficients(width);return width*(1+.10*math.sin(math.pi*v)-k*v*v)
def rake(width):return coefficients(width)[1]
def surface(u,v,height,width,base):
    b=breadth(v,width)
    return (.32+(.30*math.sin(math.pi*v)+.025*math.sin(math.pi*((8*v)%1))**2)*math.sin(math.pi*u),
            base+height*v+height*rake(width)*(1-u)*v**2.2,
            b*(u-.70)-.045*width*v*v)
