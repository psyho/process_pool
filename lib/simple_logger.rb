require File.join(File.expand_path(File.dirname(__FILE__)), 'init')

class SimpleLogger
  LEVELS = [:debug, :info, :warn, :error, :fatal]

  attr_accessor :level

  def initialize(level = :info)
    self.level = level
  end

  LEVELS.each do |level|
    define_method(level) do |msg|
      idx = LEVELS.index(level)
      if idx >= LEVELS.index(self.level)
        puts "Process #{Process.pid}: [#{level.to_s.upcase}] #{msg}"
      end
    end
  end

end