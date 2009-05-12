require "builder"
require 'pathname'
require 'silhouette/finder'

module Silhouette
  
  class SourceFile
    def initialize(path, covered_lines)
      @path = path
      @coverage = covered_lines
      @in_rdoc_comment = false
      @lines = []
    end
    
    attr_reader :path
    
    def update_coverage
      @lines = File.readlines @path
      i = 0
      @lines.each do |line|
        i += 1
        next if @coverage[i]
        if code = noop_line(line)
          @coverage[i] = code
        end
      end
      
      @largest = @coverage.compact.max do |a,b|
        a.to_i <=> b.to_i
      end
      
      @convertor = Silhouette::MethodFinder.for_syntax "ruby"
      @syn_lines = @convertor.convert @lines.join(""), false
      
      @methods = @convertor.methods
      @missed_methods = []
      @missed_methods_start = []
      
      @method_starts = []
      
      # Calculate the LOC and missed lines per method.

      @methods.each do |mp|
        next unless mp.first_line and mp.last_line
        (mp.first_line + 1).upto(mp.last_line - 1) do |line|
          code = @coverage[line]
          mp.loc += 1 unless code and code < 0
          mp.misses += 1 unless code
        end
        
        @method_starts[mp.first_line] = mp
        
        if mp.loc > 0 and mp.misses == mp.loc
          @missed_methods << mp
          @missed_methods_start[mp.first_line] = mp
        end
      end
    end
    
    NOOP_PATTERNS = [
      /^\s*begin/,
      /^\s*else/,
      /^\s*#/,
      /^\s*ensure/,
      /^\s*end/,
      /^\s*rescue/,
      /^\s*[}\)\]]/,
      /^\scase/        # You can have a case with no condition.
    ]
    
    def noop_line(line)
      if /^=begin/.match(line)
        @in_rdoc_comment = true
        return -1
      elsif /^=end/.match(line)
        @in_rdoc_comment = false
        return -1
      elsif @in_rdoc_comment
        return -1
      elsif /^\s*$/.match(line)
        return -2
      else
        return -1 if NOOP_PATTERNS.any? { |m| m.match(line) }  
      end
    end
    
    def to_ascii
      output = ""
      @lines.each_with_index do |line, i|
        if count = @coverage[i+1]
          output << "* "
        else
          output << "  "              
        end
        output << line
      end
      return output
    end
    
    def to_ascii_compact
      output = ""
      @lines.each_with_index do |line, idx|
        lineno = idx + 1
        count = @coverage[lineno]
        unless count
          output << ("%4s " % [lineno])
          output << line
        end
      end
      return output
    end
    
    def misses
      miss = @lines.size - @coverage.compact.size      
    end
    
    def non_executable
      @coverage.find_all { |i| i.to_i < 0 }.size
    end
    
    def to_xml(b)
      b.file(:path => @path, :total => @lines.size, :missed => misses) do
        @coverage.each_with_index do |count, idx|
          next if idx == 0
          count = 0 unless count
          b.line(:times => count, :number => idx)
        end
      end
    end
    
    def loc
      loc = total - non_executable
    end
    
    def loc_percentage
      (((loc - misses) / loc.to_f) * 100).to_i
    end
    
    def total
      @lines.size
    end
    
    def percent
      (((total - misses) / total.to_f) * 100).to_i
    end
    
    GREEN = "#2bc339"
    RED = "#fd3333"
    
    def html_method_summary(b)
      b.table do
        b.tr do
          b.th("Method")
          b.th("LOC")
          b.th("Misses")
          b.th("Coverage", :colspan => 2)
        end
        
        color = DGRAY
        
        @methods.each do |mp|
          color = (color == DGRAY ? LGRAY: DGRAY)
          b.tr(:bgcolor => color) do
            klass = mp.klass
            klass = "Object" if klass.empty?
            b.td(:align => "left") do
              html = @path.to_s.gsub("/","--") + ".html"
              b.a(klass + "#" + mp.name, :href => "#{html}#line#{mp.first_line}")
            end
            b.td(mp.loc)
            b.td(mp.misses)
            if mp.loc == 0
              prec = 100
            else
              prec = (((mp.loc - mp.misses) / mp.loc.to_f) * 100).to_i
            end
            b.td do
              b.text! "#{prec}%"
            end
            b.td do
              percentage_bar(prec, b)
            end
          end  
        end
      end
    end
    
    def html_summary(b)
      b.td(total, :align => "right")
      b.td(:align => "right") do
        if misses == 0
          color = GREEN
        else
          color = RED
        end
        b.p(misses, :style => "color:#{color}")
      end
      b.td(:align => "right") do
        meth_misses = @missed_methods.size
        if meth_misses == 0
          color = GREEN
        else
          color = RED
        end
        b.p(meth_misses, :style => "color:#{color}")
      end
      loc_percentage = (((loc - misses) / loc.to_f) * 100).to_i
      b.td(loc, :align => "right")
      b.td { percentage_bar(loc_percentage, b) }
      b.td("#{percent}%", :align => "right")
      b.td { percentage_bar(percent, b) }
    end
    
    def percentage_bar(percent, b)
      b.table(:width => 100, :height => 15, :cellspacing => 0, 
          :cellpadding => 0, :bgcolor => RED) do
        b.tr do
          b.td do
            b.table(:width => "#{percent}%", :height => 15, :bgcolor => GREEN) do
              b.tr { b.td { } }
            end
          end
        end
      end
    end
    
    def html_header(b)
      color = "#a8b1f9"
      b.table(:width => "100%") do
        b.tr do
          b.td do
            b.text! @path.to_s
            b.a("[MAIN]", :href => "index.html")
          end
          b.td("Total Lines: #{@lines.size}", :bgcolor => color)
          if misses == 0
            ok = "green"
          else
            ok = "#fd3333"
          end
          b.td("Missed Lines: #{misses}", :bgcolor => ok)
          b.td("Non-Code Lines: #{non_executable}", :bgcolor => color)
        end
      end
    end
    
    DGRAY = "#d4d4d4"
    LGRAY = "#f4f4f4"
    
    def calculate_hotness(count)
      return DGRAY if @largest == 0
      count = 0 if Symbol === count
      return "white" unless count
      prec = (count / @largest.to_f)
      r = [2 * (1 - prec), 1].min * 255
      g = [2 * prec, 1].min * 255
      b = 0
      
      "#%02X%02X%02X" % [g, r, b]
    end
    
    def to_html(b)
      html_header(b)
      b.table(:width => "800", :class => "code",
            :cellspacing => 0, :cellpadding => 2) do
        i = 0
        missed_until = nil
        good_until = nil
        
        @syn_lines.each do |line|
          i += 1
          b.tr do
            count = @coverage[i]
            
            klass = "sourceLine"
            lcClass = "lineCount"
            ccClass = "coverageCount"
            
            tooltip = ""
            
            # mp = @missed_methods_start[i]
            if cmp = @method_starts[i]
              if cmp.misses == 0
                gmp = cmp
              elsif cmp.misses == cmp.loc
                mp = cmp
              end
            end
            
            if mp
              ccClass = "coverageMissing"
              klass = "sourceLineHighlight"
              missed_until = mp.last_line
              count = ""
              tooltip = "Method was never entered."
            elsif missed_until
              ccClass = "coverageMissing"
              missed_until = nil if missed_until == i
              count = ""
            elsif gmp
              ccClass = "coverageMethod"
              klass = "sourceLineGoodHighlight"
              good_until = gmp.last_line
              tooltip = "Method was completely covered."
            elsif good_until
              ccClass = "coverageMethod"
              good_until = nil if good_until == i
            elsif cmp
              ccClass = "coverageHit"
              klass = "sourceLinePartialHighlight"
              tooltip = "Method has #{cmp.coverage}% coverage."
            elsif count == -1 or count == -2
              lcClass = ccClass = "lineNonCode"
              count = ""
            elsif count
              lcClass = ccClass = "coverageHit"
            else
              klass = "sourceLineHighlight"
              ccClass = "coverageMissed"
              tooltip = "This line was never run."
            end
            
            b.td(:class => lcClass, :align => "right", :width => 20) do
              b.a(i, :name => "line#{i}")
            end
            
            # Don't show less than 0 counts (they are special)
            count = "" if count and count < 0
            
            b.td(count, :class => ccClass, :align => "right", :width => 20)
            
            b.td(:class => klass) do
              b.a(:title => tooltip) do         
                b.pre(:class => klass) do
                  b << line.rstrip
                end
              end
            end
=begin
            if color == RED
              color = DGRAY
              b.td(:bgcolor => color, :style => "border: medium solid red") do
                b << "<pre>#{line.rstrip}</pre>"
              end
              hotness = "white"
            else
              # Calculate the HOTNESS of the line.
              
              b.td(:bgcolor => color) do
                b << "<pre>#{line.rstrip}</pre>"
              end
              hotness = calculate_hotness count
            end
            if count and count > 0
              b.td(count, :bgcolor => hotness, :width => 65)
            end
=end
          end
        end
      end
    end
  end
  
  class CoverageProcessor < Processor
    def initialize
      @methods = Hash.new
      @files = Hash.new
      @coverage = Hash.new { |h,k| h[k] = [] }
      @process_all = false
      @total_lines = 0
      @total_missed = 0
      @match_files = nil
      @css = "default.css"
    end
    
    attr_accessor :process_all, :match_files, :css
    
    def process?(file)
      return true if @process_all
      return false if file == "(eval)"
      
      if @match_files
        return @match_files.match(file.to_s)
      end
      
      if file[0] == ?/
        return false
      end
      
      return true
    end
    
    def add_line(file, line)
      fc = @coverage[file]
      if fc[line]
        fc[line] += 1
      else
        fc[line] = 1
      end
    end
    
    def process_call(thread, meth, file, line, clock)
      return unless @files.keys.include? file
      add_line file, line
    end
    
    def process_method(idx, klass, kind, meth)
      @methods[idx] = [klass, kind, meth].to_s
    end
    
    def process_file(idx, file)
      return unless process? file
      @files[idx] = file
    end

    def process_line(thread, meth, file, line, clock)
      return unless @files.keys.include? file
      add_line file, line      
    end
    
    attr_reader :coverage, :files
    
    def find_in_paths(file)
      $:.each do |path|
        cp = File.join(path, file)
        return cp if File.exists? cp
      end
      
      return file
    end
    
    def processed_files
      indexs = @coverage.keys.sort do |a,b|
        @files[a].to_s <=> @files[b].to_s
      end
      
      indexs.each do |idx|
        hits = @coverage[idx]
        file = @files[idx]
        if file
          unless File.exists? file
            file = find_in_paths(file)
          end
          path = Pathname.new(file)
          yield(path.cleanpath, hits)
        end
      end
    end
    
    def num_files
      @coverage.find_all { |i,h| @files[i] }.size
    end
    
    WONLY = /^\s*(end)?\s*$/
    
    def each_file
      processed_files do |file, hits|
        sf = SourceFile.new(file, hits)
        sf.update_coverage
        @total_lines += sf.loc
        @total_missed += sf.misses
        yield sf
      end
    end
    
    def to_ascii(compact=false)
      output = ""
      processed_files do |file, hits|
        sf = SourceFile.new(file, hits)
        sf.update_coverage
        output << "================ #{file} (#{sf.total} / #{sf.loc} / #{sf.misses} / #{sf.loc_percentage}%)\n"
        if compact
          output << sf.to_ascii_compact
        else
          output << sf.to_ascii
        end
      end
      return output
    end
    
    def stats
      output = ""
      output << "Total files: #{num_files}\n"
      output << "\n"
      total_lines = 0
      total_missed = 0
      each_file do |sf|
        output << "#{sf.path}: #{sf.total}, #{sf.loc}, #{sf.misses}, #{sf.loc_percentage}%\n"
      end
      output << "\nTotal LOC: #{total_lines}\n"
      output << "Total Missed: #{total_missed}\n"
      output << "Overall Coverage: #{overall_percent.to_i}%\n"
    end
    
    def to_xml
      output = ""
      xm = Builder::XmlMarkup.new(:target=>output, :indent=>2)
      xm.coverage(:pwd => Dir.getwd, :time => Time.now.to_i) do
        each_file do |sf|
          sf.to_xml xm
        end
      end
      
      return output
    end
    
    def overall_percent
      ((@total_lines - @total_missed) / @total_lines.to_f) * 100
    end
    
    def to_html(dir)
      dir = Pathname.new(dir)
      paths = []
      STDOUT.sync = true
      print "Writing out html (#{num_files} total):     "
      i = 1
      each_file do |sf|
        print "\b\b\b\b\b #{"%3d" % [(i / num_files.to_f) * 100]}%"
        path = dir + "#{sf.path.to_s.gsub("/","--")}.html"
        sum = dir + "#{sf.path.to_s.gsub("/","--")}-summary.html"
        
        paths << [path, sum, sf]
        path.open("w") do |fd|
          xm = Builder::XmlMarkup.new(:target=>fd, :indent=>2)
          xm.html do
            xm.head do
              xm.link :rel => "stylesheet", :type => "text/css", :href => @css
            end
            xm.body do
              sf.to_html xm
            end
          end
        end
        sum.open("w") do |fd|
          xm = Builder::XmlMarkup.new(:target => fd, :indent => 2)
          xm.html do
            xm.body do
              sf.html_method_summary xm
            end
          end
        end
        i += 1
      end
      
      css = dir + @css
      unless css.exist?
        css.open("w") do |fd|
          fd << File.read(File.join(File.dirname(__FILE__), @css))
        end
      end
      
      color2 = "#dedede"
      color1 = "#a8b1f9"
      
      cur_color = color2
      
      index = dir + "index.html"
      index.open("w") do |fd|
        xm = Builder::XmlMarkup.new(:target => fd, :indent => 2)
        xm.html do
          xm.body do
            xm.h3 "Code Coverage Information"
            xm.h5 do
              xm.text!("Total Coverage: ")
              xm.b("#{overall_percent.to_i}%")
            end
            xm.h5 do
              xm.text!("Number of Files: ")
              xm.b(num_files)
            end
            
            xm.table(:cellpadding => 3, :cellspacing => 1) do
              xm.tr do
                xm.th("File")
                xm.th("Total")
                xm.th("Missed")
                xm.th("Methods Missed")
                xm.th("LOC")
                xm.th("LOC %")
                xm.th("Coverage")
                xm.th("Coverage %")
              end
              paths.each do |path, sum, sf|
                cur_color = (cur_color == color1 ? color2 : color1)
                xm.tr(:bgcolor => cur_color) do
                  xm.td do
                    xm.a(sf.path, :href => path.basename)
                    xm.a("[M]", :href => sum.basename)
                  end
                  sf.html_summary(xm)
                end
              end
            end
          end
        end
      end
      
      puts "\b\b\b\b\b done."
    end
  end
end
