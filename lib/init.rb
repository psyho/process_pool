require 'json'

%w{process_pool simple_queue}.each do |file|
  require File.expand_path(File.join(File.dirname(__FILE__), file))  
end
