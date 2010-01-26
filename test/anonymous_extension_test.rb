require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper'))

class AnonymousExtensionTest < Test::Unit::TestCase

  should "raise ArgumentError when called with an unsupported method" do
    assert_raises ArgumentError do
      AnonymousExtension.new(:unsupported_method) {}
    end
  end

  AnonymousExtension::SUPPORTED_EXTENSION_METHODS.each do |method_name|
    should "not raise anything when called with #{method_name}" do
      assert_nothing_raised do
        AnonymousExtension.new(method_name) {}
      end
    end

    context "with method #{method_name}" do
      setup do
        @value = 0
        @ext = AnonymousExtension.new(method_name) { |x| @value = x }
      end

      should "execute the block when right method is called" do
        @ext.send(method_name, 1)
        assert_equal 1, @value
      end

      AnonymousExtension::SUPPORTED_EXTENSION_METHODS.each do |other_method|
        next if method_name == other_method

        should "not execute the block when #{other_method} is called" do
          @ext.send(other_method, 1)
          assert_equal 0, @value
        end
      end
    end

  end

end