def uv_fourier(best,nx,ny,options)
  # u=(x+y)/2, v=y-x ... both range from 0 to 1
  # x=u-v/2, y=u+v/2
  kernel = options['kernel']
  max_v = options['max_v']
  short_wavelengths = options['short_wavelengths']
  uv = []
  best.each { |match|
    i,j,score,why = match
    x = i/nx.to_f
    y = j/ny.to_f
    u,v = xy_to_uv(x,y)
    if v.abs>max_v then next end
    uv.push([u,v,score])
  }
  m = (short_wavelengths/kernel).round # highest fourier terms; cut off any feature with a half-wavelength smaller than 1/kernel
  if m<1 then m=1 end
  # Calculate a discrete approximation to the function, with n evenly spaced points.
  discrete = []
  n_disc = short_wavelengths*m+1
  du = 1/(n_disc-1).to_f
  0.upto(n_disc-1) { |i|
    u = i*du
    sum0 = 0.0
    sum1 = 0.0
    uv.each { |p|
      uu,vv,score = p
      weight = score*Math::exp(-short_wavelengths*(uu-u).abs/kernel)
      sum0 += weight
      sum1 += weight*vv
    }
    avg = sum1/sum0 # weighted average of v values
    discrete.push(avg)
  }
  b = fourier_analyze(discrete,m) # Fourier analyze on [0,1], period P=2, treating it as an odd function on [-1,1].
  print "b=#{b}\n"
  errs = []
  best.each { |match|
    i,j,score,why = match
    u,v = xy_to_uv(i/nx.to_f,j/ny.to_f)
    v_pred = evaluate_fourier(b,u)
    errs.push((v-v_pred).abs)
  }
  bad_error = find_percentile(errs,0.8)
  improved = []
  best.each { |match|
    i,j,score,why = match
    u,v = xy_to_uv(i/nx.to_f,j/ny.to_f)
    v_pred = evaluate_fourier(b,u)
    if (v-v_pred).abs>bad_error+2.0/nx then next end
    improved.push(match)
  }
  return b,improved
end

def xy_to_uv(x,y)
  u=(x+y)/2.0
  v=y-x
  return [u,v]
end

def improve_matches_using_light_cone(best,nx,ny,options)
  # Now we have candidates (i,j). The i and j can be transformed into (x,y) coordinates on the unit square.
  # The points consist partly of a "path" of correct matches close to the main diagonal and partly of a uniform background of false matches.
  # Now use the relationships between the points to improve the matches.
  # For speed, make an index of matches by j.
  by_j = []
  0.upto(ny-1) { |j|
    by_j.push([])
  }
  best.each { |match|
    i,j,score,why = match
    by_j[j].push(match)
  }
  # For each point (x,y), we have a "light cone" of points (x',y') such that x'-x and y'-y have the same sign.
  # If two points are both valid, then they should be inside each other's light cones.
  # Look at correlations with nearby points to get a new, improved set of scores.
  improved = []
  kernel = options['kernel']
  cut_off = options['cut_off']
  self_preservation = options['self_preservation']
  best.each { |match|
    i,j,score,why = match
    # draw a box around (i,j).
    i0 = kernel_helper(i-kernel*nx,-0.5,nx)
    i1 = kernel_helper(i+kernel*nx, 0.5,nx)
    j0 = kernel_helper(j-kernel*ny,-0.5,ny)
    j1 = kernel_helper(j+kernel*ny, 0.5,ny)
    # The box contains four quadrants, two inside the light cone and two outside. Sum over scores
    # in the quadrants, with weights of +1 and -1. The result averages to zero if we're just in a region of background.
    # The edges of the box can go outside the unit square, which is OK -- see below.
    sum = 0.0
    j0.upto(j1) { |j_other|
      by_j[j_other%ny].each { |match_other|
        # Mod by ny means we wrap around at edges; this is kind of silly, but actually makes sense statistically for bg 
        # and in terms of the near-diagonal path of good matches. Similar idea for logic involving wrap and nx below.
        i_other,dup,score_other,why_other = match_other
        i_other_unwrapped = nil
        (-1).upto(1) { |wrap|
          ii = i_other+wrap*nx
          if i0<=ii and ii<=i1 then i_other_unwrapped=ii end
        }
        if i_other_unwrapped.nil? then next end
        sign = (i_other <=> i)*(j_other <=> j) # +1 if inside light cone, -1 if outside, 0 if on boundary
        sum = sum + score_other*sign
      }
    }
    sum = sum + self_preservation*score # Otherwise an isolated point gets a score of zero. But don't preserve outliers too much, either.
    joint = score*sum
    if joint<0 then next end
    joint = Math::sqrt(joint)
    improved.push([i,j,joint,why])
  }
  improved.sort! {|a,b| b[2] <=> a[2]} # sort in decreasing order by score
  best_score = improved[0][2]
  improved = improved.select {|match| match[2]>=cut_off*best_score}.map {|match| [match[0],match[1],match[2]/best_score,match[3]]}
  0.upto(options['n_matches']-1) { |k|
    i,j,score,why = improved[k]
    if score.nan? then die("score is NaN") end
    if i.nil? or j.nil? then next end
    x,y = [i/nx.to_f,j/ny.to_f]
    print "x,y=#{x},#{y}\n\n"
    print "  correlation score=#{score} why=#{why}\n\n\n---------------------------------------------------------------------------------------\n"
  }
  write_csv_file("a.csv",improved,1000,nx,ny,nil)
  return improved
end

def kernel_helper(i,d,n)
  ii = (i+d).round
  if ii==i and d<0.0 then ii=i-1 end
  if ii==i and d>0.0 then ii=i+1 end
  return ii
end
