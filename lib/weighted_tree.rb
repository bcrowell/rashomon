#
# Utilities for working with a list of items, each of which have a probability.
# We want to be able to choose an item randomly, and this is tricky to do correctly due to the possibility of
# rounding if some of the probabilities are much smaller than others. Therefore we do this as a binary tree structure,
# with the probabilities balanced as well as possible.
#

def choose_randomly_from_weighted_tree(t,used)
  max_tries = 100
  1.upto(max_tries) { |i| # try this many times, max, to find one we haven't done before
    j = choose_randomly_from_weighted_tree_recurse(t)
    if not used.has_key?(j) or i==max_tries then return j end
  }
end

def choose_randomly_from_weighted_tree_recurse(t)
  if t[0] then
    # leaf node
    return t[2]
  else
    b0,b1 = t[2][0],t[2][1] # two branches
    p = b0[1]/(b0[1]+b1[1]) # probability of lower-probability branch; this avoids probability rounding to zero
    r = rand()
    if r<p then b=b0 else b=b1 end
    stats = t[3]
    #print "#{r}, #{p}, #{r<p}, weights=#{b0[1]}, #{b1[2]}, n=#{stats['n']}, depth=#{stats['depth']}\n"
    return choose_randomly_from_weighted_tree_recurse(b)
  end
end

def weighted_tree(w,labels,filter=lambda {|x| return x})
  # create a binary tree structure for use in randomly choosing elements
  # w is an array of floats giving the weights
  # labels is an array of integers or other keys to be used as labels; if nil, then as a convenience we create a list of integer labels
  # filter is used to change weights in any desired nonlinear way; should be positive and nondecreasing
  # each leaf node looks like
  #   [true, weight, label,            stats]
  # each non-lead node looks like
  #   [false,weight, [branch1,branch2],stats]
  eps = 1.0e-6
  if labels.nil? then
    labels = []
    0.upto(w.length) { |i|
      labels[i] = i
    }
  end
  if w.length==1 then
    return [true,filter.call(w[0]),labels[0],{'n'=>1,'depth'=>0}]
  end
  median = find_median(w)
  w0 = []
  l0 = []
  w1 = []
  l1 = []
  near_median_count = 0
  0.upto(w.length-1) { |i|
    near_median = (w[i]-median).abs<eps
    if near_median then near_median_count += 1 end
    if w[i]<median-eps or (near_median and (w0.length==0 or (w1.length!=0 and near_median_count%2==0))) then
      w0.push(w[i])
      l0.push(labels[i])
    else
      w1.push(w[i])
      l1.push(labels[i])
    end
  }
  if w0.length==0 or w1.length==0 then die("error in weighted_tree") end
  #print "recursing, w0 has length=#{w0.length}\n"
  b0 = weighted_tree(w0,l0,filter)
  b1 = weighted_tree(w1,l1,filter)
  depth = [b0[3]['depth'],b1[3]['depth']].max+1
  result = [false,b0[1]+b1[1],[b0,b1],{'n'=>w.length,'depth'=>depth}]
  #if depth<=3 then print result,"\n" end
  return result
end

