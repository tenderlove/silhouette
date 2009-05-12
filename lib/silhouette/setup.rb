require "silhouette_ext"

class Silhouette::Options
  
  def initialize
    @compress = true
    @follow_lines = false
    @file = "silhouette.out"
    @coverage = false
    @all = false
    @describe = false
    @location = false
  end
  
  attr_accessor :compress, :follow_lines, :file, :coverage
  attr_accessor :all, :describe, :location
  
  def detect_compressor(file)
    `which bzip2`
    if $?.exitstatus == 0
      file.replace "#{file}.bz2"
      return "bzip2 -c > #{file}"
    end
    
    `which gzip`
    if $?.exitstatus == 0
      file.replace "#{file}.gz"
      return "gzip -c > #{file}"
    end
    return nil
  end
  
  def import_env
    if ENV["SILHOUETTE_FILE"]
      @file = ENV["SILHOUETTE_FILE"]
    end
    
    if ENV["NO_COMPRESS"]
      @compress = false
    end
    
    if ENV["FOLLOW_LINES"]
      @follow_lines = true
    end
    
    if ENV["COVERAGE"]
      @coverage = true
    end
    
    if ENV["ALL"]
      @all = true
    end
  end
  
  def setup_args
    args = []

    gzip = nil
    
    output = @file
    
    unless IO === @file
      if @compress
        compress = detect_compressor(file)
        if compress
          gzip = IO.popen(compress, "w")
          output = gzip
        else
          # Couldn't auto detect a compressor.
        end
      end
    end
    
    args << output

    if @follow_lines
      args << true
    end

    if @coverage
      if @describe
        STDERR.puts "Generating coverage information only."
      end
      args << Silhouette::COVERAGE
    end

    if @all
      args << Silhouette::ALL
    end
    
    unless @location
      @location = @file
    end

    at_exit {
      Silhouette.stop_profile
      STDERR.puts "Flushed profile information to #{@location}"
    }
    
    return [args, @location]
  end
end
