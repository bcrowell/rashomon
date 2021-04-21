def fourier_analyze(y,m)
  # Find the Fourier series of the discrete approximation to a function on [0,1], period P=2, treating it as an odd function on [-1,1].
  # https://en.wikipedia.org/wiki/Fourier_series
  b = [] # sine coefficients
  dx = 1/(y.length.to_f-1)
  0.upto(m) { |j|
    b.push(0.0)
    x = 0.0
    y.each { |v|
      b[-1] += 2*v*Math::sin(Math::PI*j*x)*dx # factor of 2 is because we have the fictitious [-1,0].
      x = x+dx
    }
  }
  return b
end

def evaluate_fourier(b,x)
  # Period is 2, odd function on [-1,1].
  y = 0.0
  0.upto(b.length-1) { |i|
    y = y + b[i]*Math::sin(Math::PI*i*x)
  }
  return y
end

