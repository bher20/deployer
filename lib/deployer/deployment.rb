require 'git'
require 'optparse'
require 'logger'
require 'fileutils'
require 'time'

class Deployment
  def initialize(deploy_destination, repository, version, name, logger, working_copy_dir)
    @deploy_destination = deploy_destination
    @repository = repository
    @version = version
    @name = name
    @logger = logger
    @working_copy_dir = working_copy_dir
    @working_copy = prepare_working_copy working_copy_dir
  end

  def prepare_working_copy (working_copy)
    time_stamp = Time.now.strftime("%Y-%m-%d%H_%M_%S")

    @logger.info { "Preparing the working copy #{working_copy}" }

    if File.directory? working_copy
      @logger.info { "A directory with the same name as the working copy, #{working_copy}, already exists moving directory to #{working_copy}-#{time_stamp}.bak" }

      FileUtils.mv(working_copy, File.join(File.expand_path("..",working_copy), "#{File.basename(working_copy)}-#{time_stamp}.bak"))
    end

    @logger.info { "Creating working copy #{working_copy}" }
    Dir.mkdir working_copy

    @logger.info { "Cloning repository #{@repository}" }
    wc = Git.clone(@repository, working_copy)

    return wc
  end

  def update (tag)
    @logger.info { "Updating destination working copy #{@deploy_destination}" }
    if !File.directory? @deploy_destination
      @logger.info { "Destination does not exists, creating and cloning repository" }

      Dir.mkdir @deploy_destination
      Git.clone @repository, @deploy_destination, :path => File.expand_path("..", @deploy_destination)
    end

    @logger.info { "Opening destination working copy" }
    wc = Git.open(@deploy_destination, :log => @logger)


    @logger.info { "Fetching" }
    wc.fetch
    @logger.info { "Pulling" }
    wc.pull
    @logger.info { "Checking out tag #{tag}" }
    wc.checkout tag
  end

  def version?(tag_name)
    #Check to see if tag already exists
    begin
      @working_copy.tag(tag_name)
      return true
    rescue
      return false
    end
  end

  def deploy (deploy_source, force = false)
    @logger.info { "Deploying..." }

    @logger.info { "Coping files into working copy" }
    FileUtils.cp_r "#{deploy_source}/.", @working_copy_dir, :remove_destination=>true


    #Add the new files to the repo
    @logger.info { "Adding new files to git in the working copy" }
    @working_copy.add

    begin
      @logger.info { "Commiting changes" }
      @working_copy.commit_all("Updated: Release #{@version}")
    rescue Exception => e
      @logger.warn { "No new were detected, not commiting" }

      if !force
        raise e
      end
    end

    tag_name = @version
    @logger.info { "Creating tag #{tag_name}" }

    #Check to see if tag already exists
    if (version? tag_name)
      @working_copy.tag(tag_name)

      @logger.warn { "Tag #{tag_name} already exists, not creating." }

    else
      @working_copy.add_tag("#{tag_name}")
    end

    @logger.info { "Pushing updates to the origin master with the tag" }
    @working_copy.push 'origin', 'master', true


    update @version
  end

  def backout
    update @version
  end
end