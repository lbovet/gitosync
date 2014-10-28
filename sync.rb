class Synchronizer

  def initialize(workQueue)
    @workQueue = workQueue
  end

  def schedule(sync)
    sync.info "Scheduled"
    @workQueue.enqueue_b do
      sync.status = :RUNNING
      sync.info "Started"
      begin
        execute(sync)
        sync.status = :IDLE
        sync.info "Finished with success"
      rescue Exception => e
        sync.status = :IDLE        
        sync.info "FAILED: #{e.message}"
        sync.info "Finished with failure"
      end      
    end
  end
  
  private
  
  def execute(sync)
    sync.info "Cleaning..."
    @dir = "/tmp/gitosync/#{sync.space}"    
    FileUtils.remove_dir(@dir) if Dir.exists?(@dir)
    FileUtils.makedirs @dir
    sync.info "Cloning..."
    @git = Git.clone sync.from, sync.name, :path => @dir, :bare => true, :log => Logger.new(STDOUT)
    @git.add_remote "target", sync.to        
    @branches = "master"
    @branches = sync.branches if sync.branches
    @branches.split(",").each do |branch|
      sync.info "Pushing #{branch}"        
      @git.push "target", branch, :tags => true
    end
  end
end
