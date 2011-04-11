module Babushka
  class Shell
    attr_reader :cmd, :result, :stdout, :stderr

    def initialize cmd, opts
      @cmd, @opts = cmd, opts
    end

    def ok?; result end

    def run &block
      debug "$ #{@cmd}".colorize('grey')
      @stdout, @stderr = '', ''

      popen3_result = Babushka::Open3.popen3 @cmd do |stdin,stdout,stderr|
        unless @opts[:input].nil?
          stdin << @opts[:input]
          stdin.close
        end

        spinner_offset = -1
        should_spin = @opts[:spinner] && !Base.task.opt(:debug)

        # For very short-running commands, check for output in a tight loop.
        # The sleep below would at least halve the speed of quick #shell calls.
        # This means really quick calls (e.g. `whoami`, `pwd`, etc) aren't
        # delayed, but the CPU is only pegged for a fraction of a second on
        # slower calls (e.g. `gem env`, `make`, etc).
        1_000.times { break if stdout.ready_for_read? || stderr.ready_for_read? }

        loop {
          read_from stdout, @stdout do
            if should_spin
              print '  ' if spinner_offset == -1
              print "\b\b #{%w[| / - \\][spinner_offset = ((spinner_offset + 1) % 4)]}"
            end
          end
          read_from stderr, @stderr, :stderr

          # We sleep here because otherwise babushka itself would peg the CPU
          # while waiting for output from long-running shell commands.
          if stdout.closed? && stderr.closed?
            break
          else
            sleep 0.05
          end
        }

        print "\b\b" if should_spin unless spinner_offset == -1
      end

      @result = popen3_result == 0

      block_given? ? yield(self) : (stdout.chomp if ok?)
    end

    private

    def read_from io, buf, log_as = nil
      if !io.closed? && io.ready_for_read?
        loop {
          if (output = io.gets).nil?
            io.close
            break
          else
            debug output.chomp, :log => @opts[:log], :as => log_as
            buf << output
            yield if block_given?
          end
        }
      end
    end
  end
end
