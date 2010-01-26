# base class for process pool extensions
#
# it is not required that the extensions inherit from this class,
# it's here mostly for convenience and documentation sake 
class BaseWorkerExtension

  attr_accessor :logger, :queue, :process_pool

  # will be called before task gets executed
  # thowing :stop will halt the task execution process,
  # no other filters will be executed for this task
  def before(task)
  end

  # will be called after task gets executed
  def after(task, result)
  end

  # will be called before task gets executed
  # around is responsible for calling task.run,
  # failing to do so might result in unpredictable behavior
  # and failing to run a ProcessPool::EndTask will result in
  # the process never ending
  def around(task)
  end

  # will be called on worker startup, before executing any tasks
  def startup
  end

  # will be called on worker shutdown
  def shutdown    
  end

end