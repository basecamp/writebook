require "resque/pool/tasks"

task "resque:setup" => :environment

task "resque:pool:setup" do
  ActiveRecord::Base.connection_handler.clear_all_connections!

  # The pool master boots Rails and then forks each worker, so hand every child
  # its own Redis and database connections instead of sharing the master's.
  Resque::Pool.after_prefork do
    Resque.redis.reconnect
    ActiveRecord::Base.establish_connection
  end
end
