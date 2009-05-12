module Silhouette
    
  # NOTE: This uses IO#write instead of IO#puts
  # because IO#write is faster as it does a quick test
  # to see if the argument is already a string and just
  # writes it if it is. IO#puts calls respond_to? on 
  # all arguments to see if they are strings, which is
  # a lot slower if you do this 20,000 times.
  class ASCIIConverter < Processor
      def initialize(file)
          @io = File.open(file, "w")
      end
      
      def process_start(*args)
          @io.write "! #{args.join(' ')}\n"
      end
      
      def process_end(*args)
          @io.write "@ #{args.join(' ')}\n"
      end
      
      def process_method(*args)
          @io.write "& #{args.join(' ')}\n"
      end
      
      def process_file(*args)
          @io.write "* #{args.join(' ')}\n"
      end
      
      def process_call(*args)
          @io.write "c #{args.join(' ')}\n"
      end
      
      def process_return(*args)
          @io.write "r #{args.join(' ')}\n"
      end
      
      def process_line(*args)
        @io.write "l #{args.join(' ')}\n"
      end
      
      def close
          @io.close
      end
  end
  
  class ASCIIConverterLong < ASCIIConverter

      def initialize(file)
          @methods = Hash.new
          @files = Hash.new
          @last_method = nil
          @last_series = nil
          @skip_return = false
          super(file)
      end
      def process_method(idx, klass, kind, meth)
          @methods[idx] = [klass, kind, meth].to_s
      end
      
      def process_file(idx, file)
          @files[idx] = file
      end

      def process_call(thread, meth, file, line, clock)
          @io.puts "c #{thread} #{@methods[meth]} #{@files[file]} #{line} #{clock}"
      end        
      
      def process_return(thread, meth, file, line, clock)
          @io.puts "r #{thread} #{@methods[meth]} #{clock}"
      end
      
      def process_line(thread, meth, file, line, clock)
        @io.puts "l #{thread} #{@files[file]} #{line} #{clock}"
      end
      
      def process_call_rep(thread, meth, file, line, clock)
          if @last_method == [thread, meth, file, line] and @last_series
              @last_series += 1
              @skip_return = true
          else
              @io.puts "cal #{thread} #{@methods[meth]} #{meth} #{@files[file]} #{line} #{clock}"
          end
          
          @last_method = [thread, meth, file, line]
      end
              
      def process_return_rep(thread, meth, file, line, clock)
          if @last_method == [thread, meth, file, line]
              @last_series = 1 unless @last_series
          elsif @last_series
              p [thread, meth, @methods[meth]]
              p @last_method
              @io.puts "rep #{@last_series}"
              @last_series = nil
              @skip_return = false
          end
          return if @skip_return
          @io.puts "ret #{thread} #{@methods[meth]} #{clock}"
      end
  end
end