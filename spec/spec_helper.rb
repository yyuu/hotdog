require "rspec"

def optimize_n(n, x, options={})
  n.times.reduce(x) { |x, _|
    x.optimize(options)
  }
end
