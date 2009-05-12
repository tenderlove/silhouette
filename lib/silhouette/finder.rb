require 'syntax/convertors/html'

module Silhouette
  class MethodFinder < Syntax::Convertors::HTML
    class MethodPosition
      def initialize(name, klass)
        @name = name
        @klass = klass
        @misses = 0
        @loc = 0
      end
      
      def total
        @last_line - @first_line
      end
    
      attr_accessor :first_line, :last_line, :name, :klass, :misses, :loc
      
      def coverage
        loc_hit = @loc - @misses
        ((loc_hit / @loc.to_f) * 100).to_i
      end
    end
  
    class ClassPosition
      def initialize(name)
        @name = name
        @misses = 0
      end
      
      def total
        @last_line - @first_line
      end
    
      attr_accessor :first_line, :last_line, :name, :misses
    end
  
    def initialize(tok)
      super
      @line_no = 1
      @inner_ends = 0
      @class_path = []
      @class_stack = []
      @modules = []
      @methods = []
      @method_stack = []
      @current_method = nil
      @html = ""
      @line_start = true
    end
    
    attr_reader :methods, :modules
  
    HAS_END = %w!if begin while for until case unless!

    def process_token(tok)
      # p [tok, tok.group]
      case tok.group
      when :normal, :string, :constant
        nls = tok.count("\n")
        @line_no += nls
        @line_start = true if nls > 0
      when :class, :module
        # How to handle classes inside conditions? Don't count them.
        return unless @inner_ends == 0
        @class_path << tok.to_s
        klass = ClassPosition.new(@class_path.join("::"))
        klass.first_line = @line_no
        @modules << klass
        @class_stack << klass
        # puts "start class: #{@class_path.inspect}"
      when :method
        return unless @inner_ends == 0
        # Handle nested methods by just ignoring the nested ones.
        if @class_path.last == :def
          @inner_ends += 1
        else
          meth = MethodPosition.new(tok, @class_path.join("::"))
          meth.first_line = @line_no
          @methods << meth
          @method_stack << meth
          @class_path << :def
          # puts "start meth: #{@class_path.inspect}, #{tok}"
        end
      when :keyword
        if HAS_END.include?(tok.to_s) and @line_start
          @inner_ends += 1
          return
        elsif tok == "do"
          @inner_ends += 1
          return
        end
      
        if tok == "end"
          if @inner_ends == 0
            was_in = @class_path.pop
            if was_in == :def
              # puts "Done with method: #{@class_path.inspect}"
              @method_stack.last.last_line = @line_no
              @method_stack.pop
            else
              fin = @class_stack.pop
              if fin
                fin.last_line = @line_no
              end
            end
          else
            @inner_ends -= 1
            # puts "pending ends: #{@inner_ends}"
          end
        end
      end
      
      if tok.group != :normal
        @line_start = false
      end
    end
  
    def find(text)
      @tokenizer.tokenize(text) do |tok|
        process_token tok       
      end
    end
  
    private
  
    def html_escape(tok)
      process_token(tok)
      super
    end
  end
end
require 'pp'
if $0 == __FILE__
  con = Silhouette::MethodFinder.for_syntax "ruby"
  con.convert ARGF.read
  pp con
end