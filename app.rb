# Require the bundler gem and then call Bundler.require to load in all gems
# listed in Gemfile.
require 'bundler'
require './sync'
Bundler.require

DataMapper::Logger.new(STDOUT, :debug)

# Setup DataMapper with a database URL.
DataMapper.setup(:default, "sqlite://#{Dir.pwd}/data/db.sqlite")

# DataMapper model.
class Sync
  include DataMapper::Resource
  property :id, Serial, :key => true
  property :space, String, :length => 10..255, :required => true
  property :name, String, :length => 255, :required => true
  property :from, String, :length => 255, :required => true
  property :to, String, :length => 255, :required => true
  property :status, Enum[ :IDLE, :SCHEDULED, :RUNNING ], :default => :IDLE
  property :log, Text
end

# Finalize the DataMapper models.
DataMapper.finalize

# Tell DataMapper to update the database according to the definitions above.
DataMapper.auto_upgrade!

get '/' do
  send_file './public/index.html'
end

# Route to show all syncs of a space
get '/spaces/:space/syncs/' do
  content_type :json
  @syncs = Sync.all(:space => params[:space], :order => :name).map{|sync| sync.name}
  @syncs.to_json
end

# READ: Route to show a specific Sync
get '/spaces/:space/syncs/:name' do
  content_type :json
  @sync = Sync.first(:space => params[:space], :name => params[:name])
  if @sync
    @sync.to_json(:exclude => [:id, :space, :name])
  else
    halt 404
  end
end

# UPDATE: Route to create or update a Sync
put '/spaces/:space/syncs/:name' do
  content_type :json
  @input = JSON.parse(request.body.read)
  @input.delete("id")
  @input.delete("space")
  @input.delete("name")
  @input.delete("status")
  begin
    @sync = Sync.first_or_create({:space => params[:space], :name => params[:name]}, @input)  
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
      if @sync.save
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
  content_type :json
  @sync = Sync.first(:space => params[:space], :name => params[:name])
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

if Sync.count == 0
  Sync.create(:space => "1000", :name => "hello")
  Sync.create(:space => "1000", :name => "world", :status => :RUNNING)
end
