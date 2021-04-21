def write_csv_file(filename,best,n,nx,ny,fourier)
  File.open(filename,'w') { |f|
    0.upto(n-1) { |k|
      if k>=n then break end
      i,j,score,why = best[k]
      if i.nil? or j.nil? then next end
      x,y = [i/nx.to_f,j/ny.to_f]
      u,v = xy_to_uv(x,y)
      if fourier.nil? then
        stuff = ""
      else
        stuff = ",#{evaluate_fourier(fourier,u)}"
      end
      f.print "#{score},#{u},#{v}#{stuff}\n"
    }
  }
end

# returns contents or nil on error; for more detailed error reporting, see slurp_file_with_detailed_error_reporting()
def slurp_file(file)
  x = slurp_file_with_detailed_error_reporting(file)
  return x[0]
end

# returns [contents,nil] normally [nil,error message] otherwise
def slurp_file_with_detailed_error_reporting(file)
  begin
    File.open(file,'r') { |f|
      t = f.gets(nil) # nil means read whole file
      if t.nil? then t='' end # gets returns nil at EOF, which means it returns nil if file is empty
      return [t,nil]
    }
  rescue
    return [nil,"Error opening file #{file} for input: #{$!}."]
  end
end
