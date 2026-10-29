"""R15c preregistered continuous, monotone author-space rail displacement."""
import math
def clamp01(x):return min(1.,max(0.,x))
def smooth(x):
    x=clamp01(x);return x*x*(3.-2.*x)
def sheer(z):return 1.92+1.80*(max(0.,z)/16.)**3.2+.70*(max(0.,-z)/16.)**2.6
def quarter_y(z):return 4.38+.25*clamp01((-z-7.)/8.)**2
def displacement(y,z):
    bow=.85*math.sin(math.pi*(z-10.3)/5.4)**2 if 10.3<z<15.7 else 0.
    aft=.55*smooth((z+15.6)/1.)*smooth((-9.8-z)/1.)
    return bow*smooth((y-sheer(z)-.85)/.49)+aft*smooth((y-quarter_y(z)-.30)/.46)
