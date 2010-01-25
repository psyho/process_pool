class BaseWorkerExtension

  attr_accessor :logger, :queue, :process_pool

  def before(task)
  end

  def after(task)
  end

  def around(task)
    task.run
  end

  def startup
  end

  def shutdown    
  end

end