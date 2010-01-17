require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper'))

class SimpleQueueTest < Test::Unit::TestCase

  def setup
    @queue = SimpleQueue.create
  end

  def teardown
    @queue.close if @queue
  end

  context :create do
    should "return a queue" do
      assert @queue.is_a?(SimpleQueue)
    end

    should "return queues with different URIs every time" do
      new_queue = SimpleQueue.create
      new_queue.close
      assert new_queue.uri != @queue.uri
    end

    should "return a queue that is empty" do
      assert_equal 0, @queue.size
    end
  end

  context :get do
    setup do
      @uri = @queue.uri
    end

    should "raise an ArgumentError if queue does not exist" do
      assert_raises(ArgumentError) { SimpleQueue.get('not existing') }
    end

    should "return a queue if it does exist" do
      queue = SimpleQueue.get(@uri)
      assert queue
      assert_equal @uri, queue.uri
    end
  end

  context :pop do
    context "on a queue that contains something" do
      setup do
        @queue.push('hello')
      end

      context "pop" do
        setup do
          @result = @queue.pop
        end

        should "return 'hello'" do
          assert_equal 'hello', @result
        end

        should_change('queue size', :by => -1) { @queue.size }
      end
    end

    context 'on an empty queue' do
      context 'pop' do
        should 'block until something gets pushed' do
          pid = fork do
            queue = SimpleQueue.get(@queue.uri)
            value = queue.pop
            exit(value || 0)
          end
          sleep(0.5) # give the child process some time to start
          @queue.push(19) 
          pid, status = Process.waitpid2(pid)
          assert_equal 19, status.exitstatus
        end
      end
    end
  end

  context :push do
    context "on a queue that contains something" do
      setup do
        @queue.push('hello')
      end

      should_change('queue size', :by => 1) { @queue.size }
    end
  end

  should "work on a FIFO basis" do
    elements = [1, 2, 3, 4, 5]
    elements.each { |e| @queue.push(e) }
    popped = []
    elements.size.times do
      popped << @queue.pop
    end
    assert_equal elements, popped
  end

end