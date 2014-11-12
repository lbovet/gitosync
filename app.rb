# Require the bundler gem and then call Bundler.require to load in all gems
# listed in Gemfile.
require 'bundler'
require './sync'
require 'logger'
Bundler.require

$logger = Logger.new(STDOUT)
$logger.level = Logger::INFO

#DataMapper::Logger.new(STDOUT, :debug)

# Setup DataMapper with a database URL.
DataMapper.setup(:default, "sqlite://#{Dir.pwd}/data/db.sqlite")

synchronizer = Synchronizer.new WorkQueue.new 1

# DataMapper model.
class Sync
  include DataMapper::Resource
  property :id, Serial, :key => true
  property :login, String
  property :space, String, :length => 10..10, :required => true
  property :name, String, :length => 255, :required => true
  property :from, String, :length => 255, :required => true
  property :to, String, :length => 255, :required => true
  property :branches, String, :length => 512
  property :status, Enum[ :IDLE, :SCHEDULED, :RUNNING ], :default => :IDLE
  property :log, Text
  
  def info(message)    
    $logger.info "#{space}/#{name}: #{message}"
    self.log = self.log + "#{DateTime.now.strftime "%F %T" } - #{message}\n"
    self.save    
  end
  
end

# Finalize the DataMapper models.
DataMapper.finalize

# Tell DataMapper to update the database according to the definitions above.
DataMapper.auto_upgrade!

CLIENT_ID = ENV['GH_BASIC_CLIENT_ID']
CLIENT_SECRET = ENV['GH_BASIC_SECRET_ID']

use Rack::Session::Pool, :cookie_only => false

def checkAuth!
  if not session[:login]
    body 'Forbidden'
    halt 403
  end
end  

get '/' do
  erb :index, :locals => {:client_id => CLIENT_ID, :username => session[:login], :avatar => session[:avatar]}
end

get '/auth' do
  # get temporary GitHub code...
  session_code = request.env['rack.request.query_hash']['code']

  # ... and POST it back to GitHub
  result = RestClient.post('https://github.com/login/oauth/access_token',
                          {:client_id => CLIENT_ID,
                           :client_secret => CLIENT_SECRET,
                           :code => session_code},
                           :accept => :json)

  # extract the token and fetch user
  access_token = JSON.parse(result)['access_token']
  auth_result = JSON.parse(RestClient.get('https://api.github.com/user',
                                        {:params => {:access_token => access_token}}))
  if auth_result["login"]
    session[:login] = auth_result["login"]
    session[:avatar] = auth_result["avatar_url"]
  end
  redirect '/'
end

# Route to show all syncs of a space
get '/spaces/:space/syncs/' do
  checkAuth!
  content_type :json
  @syncs = Sync.all(:space => params[:space], :login => session[:login], :order => :name).map{|sync| sync.name}
  @syncs.to_json
end

# READ: Route to show a specific Sync
get '/spaces/:space/syncs/:name' do
  checkAuth!
  content_type :json
  @sync = Sync.first(:space => params[:space], :login => session[:login], :name => params[:name])
  if @sync
    @sync.to_json(:exclude => [:id, :space, :name, :login])
  else
    halt 404
  end
end

# UPDATE: Route to create or update a Sync
put '/spaces/:space/syncs/:name' do
  checkAuth!
  content_type :json
  @input = JSON.parse(request.body.read)
  @input.delete("id")
  @input.delete("space")
  @input.delete("name")
  @input.delete("status")
  @input.delete("login")
  begin
    @sync = Sync.first_or_create({:space => params[:space], :login => session[:login], :name => params[:name]}, @input)  
    if not @sync.new?
      @sync.update(@input)
    end
    if @sync.valid?
      if @sync.save
        @sync.to_json(:exclude => [:id, :space, :name])
      else
        halt 500      
      end
    else 
      body @sync.errors.full_messages.join("\n")   
      halt 400
    end
  rescue ArgumentError => e
        body e.message
        halt 400      
  end    
end

# RUN: Schedule a Sync for execution
post '/spaces/:space/syncs/:name' do
  content_type :json
  @sync = Sync.first(:space => params[:space], :name => params[:name])
  if @sync
    if @sync.status == :IDLE
      @sync.status = :SCHEDULED
      @sync.log = "" 
      if @sync.save
        synchronizer.schedule(@sync)
        ''
      else
        halt 500
      end
    else
      body "Cannot schedule because already scheduled or running"
      halt 409
    end
  else
    halt 404
  end
end

# DELETE: Route to delete a Sync
delete '/spaces/:space/syncs/:name' do
  checkAuth!
  content_type :json
  @sync = Sync.first(:space => params[:space], :login => session[:login], :name => params[:name])
  if @sync
    if @sync.destroy
      ''
    else
      halt 500
    end
  else
    halt 404
  end
end

# Reset status on startup
Sync.all(:status.not => :IDLE).map do |sync|
  sync.status = :IDLE
  sync.save
end
