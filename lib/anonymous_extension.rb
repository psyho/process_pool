require File.join(File.expand_path(File.dirname(__FILE__)), 'init')

class AnonymousExtension < BaseWorkerExtension

  SUPPORTED_EXTENSION_METHODS = [:before, :after, :around, :startup, :shutdown]

  def initialize(method, &block)
    raise ArgumentError.new("Unknown method: #{method}") unless SUPPORTED_EXTENSION_METHODS.include?(method)

    @method = method
    @block = lambda(&block)
  end

  SUPPORTED_EXTENSION_METHODS.each do |method_name|
    define_method(method_name) do |*args|      
      @block.call(*args) if method_name == @method      
    end
  end

end