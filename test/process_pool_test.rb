require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper')) 

class SampleQueue

  attr_accessor :data

  def initialize
    self.data = []
  end

  def close    
  end

  def uri
    'test-queue'
  end

  def push(value)
    self.data << value
  end

  def pop
    self.data.shift
  end

  def size
    self.data.size
  end

  def self.create
    new
  end

  def self.get(uri)
    new
  end

end

class SampleTask

  attr_accessor :args

  def initialize(*args)
    self.args = args
  end

  def run
    return args
  end

end

class ExceptionTask
  def run
    raise ArgumentError.new("something went wrong")
  end
end

class WrongArgumentsTask
  def initialize(x, y, z)
  end

  def run    
  end
end

class WriteToFileTask

  def initialize(path, n)
    @path = path
    @n = n
  end

  def run
    File.open(@path, 'a+') do |file|
      file.puts "task #{@n}"
    end
  end

end

class ProcessPoolTest < Test::Unit::TestCase

  context "state" do
    setup do
      @pool = ProcessPool.new(10, SampleQueue.new, SimpleLogger.new(:debug))
      @pool.stubs(:fork => 1)
      Process.stubs(:wait => 0)
    end

    should "be stopped after initialization" do
      assert @pool.is_stopped?
      assert !@pool.is_running?
      assert !@pool.is_shutdown?
    end

    should "be running after start" do
      @pool.start
      assert !@pool.is_stopped?
      assert @pool.is_running?
      assert !@pool.is_shutdown?
    end

    should "be shutdown after shutdown" do
      @pool.start
      @pool.shutdown
      assert !@pool.is_stopped?
      assert !@pool.is_running?
      assert @pool.is_shutdown?
    end

    context "invalid actions" do
      should "raise InvalidStateError when calling shutdown on a not started pool" do
        assert_raises ProcessPool::InvalidStateError do
          @pool.shutdown
        end
      end

      should "raise InvalidStateError when calling register_extension on a started pool" do
        @pool.start
        assert_raises ProcessPool::InvalidStateError do
          @pool.register_extension(BaseWorkerExtension.new)
        end
      end

      should "raise InvalidStateError when calling register_extension on a shutdown pool" do
        @pool.start
        @pool.shutdown
        assert_raises ProcessPool::InvalidStateError do
          @pool.register_extension(BaseWorkerExtension.new)
        end
      end

      should "raise InvalidStateError when calling start twice" do
        @pool.start
        assert_raises ProcessPool::InvalidStateError do
          @pool.start
        end
      end

      should "raise InvalidStateError when calling shutdown twice" do
        @pool.start
        @pool.shutdown
        assert_raises ProcessPool::InvalidStateError do
          @pool.shutdown
        end
      end

      should "raise InvalidStateError when calling schedule on a shutdown pool" do
        @pool.start
        @pool.shutdown
        assert_raises ProcessPool::InvalidStateError do
          @pool.schedule(SampleTask)
        end
      end
    end
  end

  context :schedule do
    setup do
      @queue = SampleQueue.new
      @pool = ProcessPool.new(10, @queue, SimpleLogger.new(:debug))
      @pool.stubs(:fork => 1)
    end

    should "add jobs to the queue" do
      assert_equal 0, @queue.size
      @pool.schedule(SampleTask, 1, 2, 3)
      assert_equal 1, @queue.size
      assert_equal ["SampleTask", [1, 2, 3]], @queue.pop
    end
  end

  context :start do
    setup do
      @queue = SampleQueue.new
      @workers_count = 10
      @pool = ProcessPool.new(@workers_count, @queue, SimpleLogger.new(:debug))
    end

    should "fork workers_count workers" do
      @pool.expects(:fork).times(@workers_count).returns(0)
      @pool.start
    end
  end

  context :shutdown do
    setup do
      @queue = SampleQueue.new
      @pool = ProcessPool.new(3, @queue, SimpleLogger.new(:debug))
      @pool.schedule(SampleTask)
      @pool.stubs(:fork => 1)
      @pool.start
    end

    should "schedule same number od EndTasks as worker_count" do
      Process.stubs(:wait => 0)
      @pool.shutdown
      assert_equal 4, @queue.size
      assert_equal "SampleTask", @queue.data[0].first
      (1..3).each do |n|
        assert_equal "ProcessPool::EndTask", @queue.data[n].first
      end
    end

    should "wait on all of the worker processes to end" do
      Process.expects(:wait).with(1).times(3).returns(0)
      @pool.shutdown
    end

    should "close the queue" do
      @queue.expects(:close)
      Process.stubs(:wait => 0)
      @pool.shutdown
    end
  end

  context "with default queue and two workers" do
    setup do
      @pool = ProcessPool.new(1)
      2.times { |n| @pool.schedule(SampleTask, n) }
      @pool.send(:queue).stubs(:close => nil) # so that we can inspect the queue contents 
    end

    teardown do
      SimpleQueue.get(@pool.send(:queue).uri).close
    end

    should "empty the queue before returning from shutdown" do
      assert_equal 2, @pool.send(:queue).size
      @pool.start
      @pool.shutdown
      assert_equal 0, @pool.send(:queue).size
    end

    should "empty the queue even if some tasks result in exception" do
      @pool.schedule(ExceptionTask)
      assert_equal 3, @pool.send(:queue).size
      @pool.start
      @pool.shutdown
      assert_equal 0, @pool.send(:queue).size
    end

    should "empty the queue even if some tasks can not be loaded" do
      @pool.schedule(String)
      assert_equal 3, @pool.send(:queue).size
      @pool.start
      @pool.shutdown
      assert_equal 0, @pool.send(:queue).size
    end

    should "empty the queue even if some tasks can not be initialized" do
      @pool.schedule(WrongArgumentsTask, 1)
      assert_equal 3, @pool.send(:queue).size
      @pool.start
      @pool.shutdown
      assert_equal 0, @pool.send(:queue).size
    end

  end

  def self.should_write_lines(*lines)
    should "write lines #{lines.collect{|line| line.inspect}.join(', ')} to file" do
      text = open(@path).read
      file_lines = text.split("\n").collect { |line| line.strip }
      assert_equal lines, file_lines
    end
  end

  def write_to_shared_file(str)
    File.open(@path, 'a+') do |file|
      file.puts str
    end
  end

  context "extensions" do
    setup do
      @logger = SimpleLogger.new(:debug)
      @pool = ProcessPool.new(1, SimpleQueue.create, @logger)
      @shared_file = Tempfile.new('test')
      @path = @shared_file.path
    end

    teardown do
      @shared_file.close
    end

    should "raise ArgumentError if called with nil" do
      assert_raises ArgumentError do
        @pool.register_extension nil
      end
    end

    should "inject process_pool to the extension" do
      extension = BaseWorkerExtension.new
      assert_nil extension.process_pool
      @pool.register_extension(extension)
      assert_equal @pool, extension.process_pool
    end

    should "inject logger to the extension" do
      extension = BaseWorkerExtension.new
      assert_nil extension.logger
      @pool.register_extension(extension)
      assert_equal @logger, extension.logger
    end

    context "with no extensions" do
      setup do
        @pool.schedule(WriteToFileTask, @path, 1)
        @pool.schedule(WriteToFileTask, @path, 2)

        @pool.start
        @pool.shutdown
      end

      should_write_lines "task 1", "task 2"      
    end

    context "with before extension" do
      setup do
        @pool.schedule(WriteToFileTask, @path, 1)
        @pool.schedule(WriteToFileTask, @path, 2)

        @pool.register_extension AnonymousExtension.new(:before) { |t| write_to_shared_file("before") }

        @pool.start
        @pool.shutdown
      end

      should_write_lines "before", "task 1", "before", "task 2"
    end

    context "with after extension" do
      setup do
        @pool.schedule(WriteToFileTask, @path, 1)
        @pool.schedule(WriteToFileTask, @path, 2)

        @pool.register_extension AnonymousExtension.new(:after) { |t, r| write_to_shared_file("after") }

        @pool.start
        @pool.shutdown
      end

      should_write_lines "task 1", "after", "task 2", "after"
    end

    context "with around extension" do
      setup do
        @pool.schedule(WriteToFileTask, @path, 1)
        @pool.schedule(WriteToFileTask, @path, 2)

        @pool.register_extension AnonymousExtension.new(:around) { |t|
          write_to_shared_file("around 1")
          t.run
          write_to_shared_file("around 2")
        }

        @pool.start
        @pool.shutdown
      end

      should_write_lines "around 1", "task 1", "around 2", "around 1", "task 2", "around 2"
    end

    context "with multiple around extensions" do
      setup do
        @pool.schedule(WriteToFileTask, @path, 1)
        @pool.schedule(WriteToFileTask, @path, 2)

        @pool.register_extension AnonymousExtension.new(:around) { |t|
          write_to_shared_file("around a")
          t.run
          write_to_shared_file("around b")
        }
        
        @pool.register_extension AnonymousExtension.new(:around) { |t|
          write_to_shared_file("around 1")
          t.run
          write_to_shared_file("around 2")
        }

        @pool.start
        @pool.shutdown
      end

      should_write_lines "around a", "around 1", "task 1", "around 2", "around b", "around a", "around 1", "task 2", "around 2", "around b"
    end

    context "with startup extension" do
      setup do
        @pool.schedule(WriteToFileTask, @path, 1)
        @pool.schedule(WriteToFileTask, @path, 2)

        @pool.register_extension AnonymousExtension.new(:startup) { write_to_shared_file("startup") }

        @pool.start
        @pool.shutdown
      end

      should_write_lines "startup", "task 1", "task 2"
    end

    context "with shutdown extension" do
      setup do
        @pool.schedule(WriteToFileTask, @path, 1)
        @pool.schedule(WriteToFileTask, @path, 2)

        @pool.register_extension AnonymousExtension.new(:shutdown) { write_to_shared_file("shutdown") }

        @pool.start
        @pool.shutdown
      end

      should_write_lines "task 1", "task 2", "shutdown"
    end

    context "with all kinds of extensions" do
      setup do
        @pool.schedule(WriteToFileTask, @path, 1)
        @pool.schedule(WriteToFileTask, @path, 2)

        @pool.register_extension AnonymousExtension.new(:around) { |t|
          write_to_shared_file("around 1")
          t.run
          write_to_shared_file("around 2")
        }

        @pool.register_extension AnonymousExtension.new(:before) { |t| write_to_shared_file("before") }
        @pool.register_extension AnonymousExtension.new(:after) { |t, r| write_to_shared_file("after") }

        @pool.register_extension AnonymousExtension.new(:startup) { write_to_shared_file("startup") }
        @pool.register_extension AnonymousExtension.new(:shutdown) { write_to_shared_file("shutdown") }

        @pool.start
        @pool.shutdown
      end

      should_write_lines "startup", "before", "around 1", "task 1", "around 2", "after", "before", "around 1", "task 2", "around 2", "after", "shutdown"
    end
  end

end