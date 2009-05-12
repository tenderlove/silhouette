require 'pp'

module Silhouette
        
    class Processor
        def initialize(emitter)
            @emitter = emitter
            @processors = Hash.new
            methods.grep(/^process_(.*)/) do |meth|
                @processors[$1.to_sym] = meth.to_sym 
            end
        end
        
        def run
            @emitter.parse do |kind, *args|
                if meth = @processors[kind]
                    __send__(meth, *args) 
                end
            end
        end
        
        def process_start(*a)
        end
        
        def process_end(*a)
        end
        
        def process_method(*a)
        end
        
        def process_file(*a)
        end
        
        def process_line(*a)
        end
        
        def process_call(*a)
        end
        
        def process_return(*a)
        end
    end

    class CallTree
        def initialize
        end 
    end
    
    class CallNode
        def initialize
        end 
    end
    
    class ProfileNode
        attr_accessor :total_sec, :self_sec, :calls
        attr_accessor :callers, :children
        
        attr_reader :key
        def initialize(key, children=[])
            @key = key
            @total_sec = 0.0
            @self_sec = 0.0
            @calls = 0
            @callers = []
            @children = children
        end
        
        def inc_call!
            @calls += 1
        end
        
        def add_cost(cost, last)
            @total_sec += cost
            @self_sec += (cost - last)
        end
        
        def percentage(total)
            @self_sec / total * 100.0
        end
        
        def self_ms_per_call
            (@self_sec * 1000.0 / @calls)
        end
        
        def total_ms_per_call
            (@total_sec * 1000.0 / @calls)
        end
        
        alias method key
    end

    class DefaultProfiler < Processor
        
        def initialize(per_callsite=false)
            @threads = Hash.new
            @map = Hash.new
            @cs_map = Hash.new
            @timestamps = []
            @clocks = []
            @pid = nil
            @total = 0.0
            @filters = []
            @methods = Hash.new
            @files = Hash.new
            @per_callsite = per_callsite
        end
    
        def stack(thread)
            @threads[thread] ||= []
        end
    
        attr_reader :directory, :timestamps
    
        def data
            @map
        end
    
        def data=(d)
            @map = d
        end
            
        def save(file)
            File.open(file, "w") do |f|
                f << Marshal.dump(self)
            end
        end
        
        def process_start(*args)
            @directory, @clock_per_sec, @start_clock = *args
        end
    
        def process_end(*args)
            @final_clock, @profiler_cost = *args
        end
    
        def process_method(*args)
            idx = args.shift
            @methods[idx] = args
        end
    
        def process_file(*args)
            idx = args.shift
            @files[idx] = args
        end
    
        def process_call(thread, method, file, line, clock)
            st = (@threads[thread] ||= [])
            st.push [clock, 0.0, [method, file, line], []]
        end
    
        def process_return(thread, method, file, line, clock)
            st = (@threads[thread] ||= [])
            if tick = st.pop
=begin
                if tick.last != method
                    STDERR.puts "Unmatched return for #{method} (#{tick.last})"
                    return
                end
                if @per_callsite
                    key = [method, loc]
                else
                    key = method
                end
=end
                cost = (clock.to_f - tick[0]) / @clock_per_sec

                # Add to the callers callee cost and child list.
                if last = st.last
                    last[1] += cost
                    last[3] << method
                    caller = last[2]
                else
                    caller = nil
                end

                # Record the data for the method.
                key = method
                node = (@map[key] ||= ProfileNode.new(key, tick.last))
                node.inc_call!
                node.add_cost cost, tick[1]
                node.callers << caller.first if caller
                
#                 data = (@map[key] ||= [0, 0.0, 0.0, key, tick.last, []])
#                 data[0] += 1
#                 data[2] += cost
#                 data[1] += cost - tick[1]
#                 data[5] << caller.first if caller # Just the method index

                # Record the data for the method at callsite
#                 key = [method, file, line]
#                 data = (@cs_map[key] ||= [0, 0.0, 0.0, key, tick.last, caller])
#                 data[0] += 1
#                 data[2] += cost
#                 data[1] += cost - tick[1]
            
            end
        end
        
        def print(f=STDERR, max=nil)
            print_flat_profile(f, max)
            print_tree_profile(f, max)
        end
        
        def total_seconds
            (@final_clock - @start_clock  ).to_f / @clock_per_sec
        end
        
        def print_flat_profile(f=STDERR, max=nil)
            f.puts "Number of threads: #{@threads.size}"
            if @per_callsite
                f.puts "Profiling based on method call and call site."
            else
                f.puts "Profiling based on method call." 
            end
            f.puts "Cost of profiler: #{@profiler_cost.to_f / @clock_per_sec} seconds."
            
            total = total_seconds
            total = 0.01 if total == 0
            f.puts "\nFlat profile (#{total} total seconds):"
            data = @map.values
            data.sort! { |a,b| b.self_sec <=> a.self_sec }
            # data.sort! { |a,b| b[1] <=> a[1] }
            sum = 0
            f.puts "  %      total     self              self     total"
            f.puts " time   seconds   seconds    calls  ms/call  ms/call  name"
            count = 0
            data.each do |node|
            #data.each do |calls, self_ms, total_ms, sig|
                sum += node.self_sec
                
                prec = node.percentage(total)
                next if prec < 0.01
                
                f.printf "%6.2f ",  prec
                f.printf "%8.2f ",  sum
                f.printf "%8.2f ",  node.self_sec
                f.printf "%8d ",    node.calls
                f.printf "%8.2f ",  node.self_ms_per_call
                f.printf "%8.2f ",  node.total_ms_per_call
                f.puts get_name(node.method)
            
                count += 1
                return if max and count > max
            end
        end
        
        def collapse_children(cl, map)
            out = Hash.new { |h,k| h[k] = 0 }

            # p cl
            cl.each do |c|
                out[c] += 1
            end
            
            data = []
            out.each do |meth,times|
                # ch_ms = (map[meth][1] * 1000) / map[meth][0]
                data << [meth, times, map[meth]]
            end
            
            data.sort! { |a,b| b[2].self_sec <=> a[2].self_sec }
            data
        end
        
        def show_callers(callers, map)
        end
        
        def print_tree_profile(f=STDERR, max=nil)
            width = 40
            f.puts
            f.puts "Call Tree Profile: "
            f.puts "index       calls      ms/     self    total"
            f.puts "                      call     sec      sec"
            map = @map

            data = map.values
            data.sort! { |a,b| b.self_sec <=> a.self_sec }
            data.each do |pn|
                next if pn.total_ms_per_call < 0.01
                data = collapse_children(pn.callers, map)

                data.each do |meth, called_times, cn|
                    times = map[meth].children.find_all { |i| i == pn.method }.size
                    if times == 0
                        times = "?"
                    else
                        called_times = called_times / times
                    end
                    vars = ["", "#{times}/#{called_times}", "-", "-", 
                        "-", get_name(cn.method)]
                    f.puts "%-2s %14s %8s %8s %8s    %s [#{meth}]" % vars
                end

                cl = collapse_children(pn.children, map)
                chlines = []
                sum = 0
                cl.each do |meth, times, cn|
                    self_ms = cn.total_ms_per_call * times
                    sum += self_ms
                    self_sec = self_ms.to_f / 1000
                    total = self_sec * pn.calls
                    
                    next if total < 0.01
                    vars = ["", times, cn.total_ms_per_call, 
                        self_sec, total, get_name(cn.method)]
                    chlines << "%-8s %8d %8.2f %8.2f %8.2f    %s [#{meth}]" % vars
                end
                vars = ["[#{pn.method}]", pn.calls, 
                    pn.self_ms_per_call, pn.self_sec, pn.total_sec, 
                    get_name(pn.method)]
                f.puts "%-8s %8d %8.2f %8.2f %8.2f  %s" % vars
                f.puts *chlines if chlines.size > 0
                f.puts "-" * 70
            end
        end
    
        def get_name(info, per_cs=false)
            if per_cs
                @methods[info.first].to_s + " @ " + @files[info[1]].to_s + ":#{info[2]}"
            else
                @methods[info].to_s
            end
        end
    end

    class EntryPointProfiler < DefaultProfiler
        def initialize(file, sig, depth=nil)
            super(file)
            @entry = sig
            @start = Hash.new { |h,k| h[k] = false }
            @max_depth = depth
            @depth = Hash.new { |h,k| h[k] = 0 }
        end

        def process_call(thread, klass, kind, method, time)
            #return unless thread == "b7533c3c"
            if @entry == [klass, kind, method].to_s
                @start[thread] = true
                STDERR.puts "entered #{@entry} at #{time} in #{thread}"
                return
            end
            
            return unless @start[thread]
           
            # puts "#{[klass, kind, method]} (#{@depth[thread]})"

            @depth[thread] += 1

            #puts "call"
            #p @depth
            return if @max_depth and @depth[thread] > @max_depth
            # puts "call: #{@depth} #{[klass, kind, method]}"
            super
        end

        def process_return(thread, klass, kind, method, time)
            #return unless thread == "b7533c3c"
            if @entry == [klass, kind, method].to_s
                @start[thread] = false
                STDERR.puts "exitted #{@entry} at #{time} in #{thread}"
                return
            end

            return unless @start[thread]
            
            if !@max_depth or @depth[thread] <= @max_depth
                super
            end
            
            @depth[thread] -= 1
        end

        def print(f=STDERR,max=nil)
            f.puts "Calls only shown if performed from #{@entry}."
            if @max_depth
                f.puts "Calls only processed #{@max_depth} level(s) deep."
            end
            f.puts
            super
        end
    end
end
