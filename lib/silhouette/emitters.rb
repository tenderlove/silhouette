module Silhouette
  class InvalidFormat < Exception; end
  
  def self.emitters
      out = []
      constants.each do |name|
          con = const_get(name)
          if Class === con and con.superclass == Emitter
              out << con
          end
      end
      out
  end
  
  def self.find_emitter(file)

    if file == "-"
      io = STDIN
    
    elsif /.bz2$/.match(file)
      io = IO.popen("bzip2 -dc '#{file}'")
    elsif /.gz$/.match(file)
      io = IO.popen("gzip -dc '#{file}'")
    else
      raise "Unknown file" unless File.exists?(io)
      io = File.open(file)
    end

    emitters.each do |em|
      begin
        return em.new(io)
      rescue InvalidFormat
      end
    end

    raise InvalidFormat, "Unable to find valid emitter"
  end
  
  class Emitter
      def initialize(processor=nil)
          @processor = processor
      end
      
      attr_accessor :processor
  end 
  
  class BinaryEmitter < Emitter
      MAGIC = "<>"
      
      def initialize(file, processor=nil)
          if file.kind_of? String
              raise "Unknown file" unless File.exists?(file)
              @io = File.open(file)
          else
              @io = file
          end
          
          magic = @io.read(2)
          raise InvalidFormat unless magic == MAGIC
          
          @method_size = "S"
          @file_size = "S"
          @ret_call_fmt = "i#{@method_size}#{@file_size}ii"
          @ret_call_size = 16
          super(processor)
      end
  
      class DoneParsing < Exception; end
  
      def parse
          begin
              loop { emit }
          rescue DoneParsing
          end
      end
      
      FIXED_SIZE = {
          ?c => 20,
          ?r => 20,
          ?@ => 8
      }
  
      def next_cmd
          str = @io.read(1)
          raise DoneParsing unless str
      
          cmd = str[0]
          if [?!, ?*, ?&].include? cmd
              size = @io.read(4).unpack("i").first
          else
              size = FIXED_SIZE[cmd]
          end
              
          [cmd, size, @io.read(size)]
      end
      
      def parse
          begin
          # Use "while true" instead of "loop" because loop is
          # really a method call.
          while true
              data = @io.read(1)
              raise DoneParsing unless data
      
              cmd = data[0]
          
              # These are hardcoded in here for speed.
              if cmd == ?r or cmd == ?c or cmd == ?l
                  size = @ret_call_size
              elsif cmd == ?@
                  size = 8
              else
                  size = @io.read(4).unpack("i").first
              end
          
              proc = @processor
              data = @io.read(size)
          
              case cmd
              when ?r
                  parts = data.unpack(@ret_call_fmt)
                  @processor.process_return(*parts)
                  # return [:return, *parts]
              when ?c
                  parts = data.unpack(@ret_call_fmt)
                  @processor.process_call(*parts)
              when ?l
                  parts = data.unpack(@ret_call_fmt)
                  @processor.process_line(*parts)
                  # return [:call, *parts]
              when ?!
                  parts = data.unpack("Z#{size - 8}ii")
                  @processor.process_start(*parts)
                  # return [:start, *parts]
              when ?@
                  parts = data.unpack("ii")
                  @processor.process_end(*parts)
                  # return [:end, *parts]
              when ?&
                  parts = data.unpack("ia#{size - 4}")
                  parts += parts.pop.split("\0")
                  @processor.process_method(*parts)
                  # return [:method, *parts]
              when ?*
                  parts = data.unpack("iZ#{size - 4}")
                  @processor.process_file(*parts)
                  # return [:file, *parts]
              when ?(
                  @method_size = "I"
                  @ret_call_size += 2
                  @ret_call_fmt = "i#{@method_size}#{@file_size}ii"
              when ?)
                  @file_size = "I"
                  @ret_call_size += 2
                  @ret_call_fmt = "i#{@method_size}#{@file_size}ii"
              else
                  raise "Unknown type '#{cmd.chr}'"
              end
          end
          
          # This means we're done.
          rescue DoneParsing
          end
      end
  end
end