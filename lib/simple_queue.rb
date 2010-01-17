require 'rubygems'
require 'json'
require 'tempfile'

class SimpleQueue

  attr_reader :uri

  def close
    File.delete(uri)
  end

  def push(value)
    with_queue_file do |file|
      contents = file.read
      queue = JSON.parse(contents)
      queue.push(value)
      store_queue(file, queue)
    end
  end

  def pop
    result = nil
    queue_empty = true

    while queue_empty
      queue_empty, result = pop_nowait()
      sleep(0.1) if queue_empty
    end
    
    return result
  end

  def size
    contents = ''
    with_queue_file do |file|
      contents = file.read
    end
    return JSON.parse(contents).size
  end

  def self.create
    file = Tempfile.new('simple_queue')
    file.puts [].to_json
    uri = file.path
    file.close
    return new(uri)
  end

  def self.get(uri)
    raise ArgumentError.new("Queue file must exist: #{uri}") unless File.exists?(uri)
    return new(uri)
  end

  protected

  attr_writer :uri

  def initialize(uri)
    self.uri = uri
  end

  def with_queue_file(&block)
    file = File.new(uri, 'r+')
    if file.flock(File::LOCK_EX)
      block.call(file)
    end
    file.close
  end

  def store_queue(file, queue)
    file.truncate(0)
    file.seek(0)

    file.puts queue.to_json
  end

  def pop_nowait
    queue_empty = true
    result = nil
    with_queue_file do |file|
      contents = file.read
      queue = JSON.parse(contents)
      unless queue.empty?
        queue_empty = false
        result = queue.shift
        store_queue(file, queue)
      end
    end
    return queue_empty, result
  end

end