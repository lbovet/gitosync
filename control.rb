require 'rubygems'
require 'daemons'



pwd = Dir.pwd
Daemons.run_proc('gitosync', {:dir_mode => :normal, :dir => "/var/opt/sinatra/pids", :log_output => true}) do
  Dir.chdir(pwd)
  exec "ruby app.rb"
end

