module Packager
  class Log < ActiveSupport::Logger

    attr_reader :start_time, :datetime_format, :output_level

    def initialize(*args)
      @start_time = Time.now
      @datetime_format = '%Y-%m-%d %H:%M:%S'
      @output_level = args[0]

      # reset the first argument to the log file for the super call
      args[0] = 'log/packager.log'
      super

      self.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.strftime(@datetime_format)} #{severity} #{msg}\n"
      end

      self.info "Packager started"
    end

    def close
      end_time = Time.now
      duration = (end_time - @start_time) / 1.minute
      self.info "Duration: #{duration}"
      self.info "Packager ended"
      super
    end

    def info(str)
      print_and_flush(str)
      super
    end

    def warn(str)
      print_and_flush(str)
      super
    end

    def error(str)
      print_and_flush(str)
      super
    end

    # Method for printing to the shell without puts newline. Good for showing
    # a shell progress bar, etc...
    def print_and_flush(str)
      case @output_level
      when 'verbose'
        puts str
      when 'minimal'
        case caller_locations(1,1)[0].label
        when 'info'
          print ".".green
        when 'warn'
          print "-".yellow
        when 'error'
          print 'X'.red
        end
        $stdout.flush
      end
    end
  end
end
