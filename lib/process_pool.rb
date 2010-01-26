require File.join(File.expand_path(File.dirname(__FILE__)), 'init')

class ProcessPool

  class InvalidStateError < StandardError;
  end

  attr_reader :workers_count

  def initialize(workers_count, queue = SimpleQueue.create, logger = SimpleLogger.new)
    self.state = :stopped
    self.logger = logger
    self.workers_count = workers_count
    self.queue = queue
    self.worker_pids = []
    self.extensions = []
  end

  def schedule(job_class, *args)
    raise InvalidStateError.new('Can not add more jobs after shut down was called') if is_shutdown?
    logger.debug("Scheduling task #{job_class}(#{args.collect{ |a| a.inspect }.join(', ')})")
    push_task(job_class, args)
  end

  def register_extension(extension)
    raise InvalidStateError.new('Can not register extensions once the pool is started.') unless is_stopped?
    raise ArgumentError.new('extension can not be nil') unless extension

    extension.process_pool = self if extension.respond_to?(:process_pool=)
    extension.logger = logger if extension.respond_to?(:logger=)

    extensions << extension
  end

  def start
    raise InvalidStateError.new('Can not start a pool more than once') unless is_stopped?
    logger.info("Starting process pool")
    self.state = :running

    workers_count.times do
      pid = fork do
        run_extensions(:startup)
        at_exit { run_extensions(:shutdown) }
        child_queue = get_child_queue()
        while true
          task_class, args = child_queue.pop
          begin
            task = get_task_class(task_class).new(*args)
            run_extensions(:before, task) unless task.is_a?(EndTask)
            result = task.run
            run_extensions(:after, task, result)
          rescue => e
            logger.warn("Exception occurred while executing task #{task_class}(#{args}): #{e}")
          end
        end
      end
      self.worker_pids << pid
    end
  end

  def shutdown
    raise InvalidStateError.new('Can not shut down pool that is not running') unless is_running?
    logger.info("Shutting down process pool")
    self.state = :shutdown

    workers_count.times do
      push_task(EndTask, [])
    end

    worker_pids.each do |pid|
      Process.wait(pid)
    end

    queue.close
  end

  def is_running?
    return state == :running
  end

  def is_stopped?
    return state == :stopped
  end

  def is_shutdown?
    return state == :shutdown
  end

  protected

  attr_accessor :state, :logger, :queue, :worker_pids, :extensions
  attr_writer :workers_count

  def push_task(job_class, args)
    queue.push([job_class.name.to_s, args])
  end

  def get_child_queue
    queue.class.get(queue.uri)
  end

  # this is taken from ActiveSupport (String#constantize)
  def get_task_class(class_name)
    unless /\A(?:::)?([A-Z]\w*(?:::[A-Z]\w*)*)\z/ =~ class_name
      raise NameError, "#{class_name.inspect} is not a valid constant name!"
    end

    Object.module_eval("::#{$1}", __FILE__, __LINE__)
  end

  def run_extensions(method, *args)
    extensions.each do |extension|
      if extension.respond_to?(method)
        extension.send(method, *args)
      end
    end
  end

  class EndTask
    def run
      exit(0)
    end
  end

end