class Jets::Builders
  class TmpGems
    LAMBDA_SIZE_LIMIT = 250 # Total lambda limit is 250MB

    include Util

    # When stage/code + stage/opt is the Lambda limit we'll create a stage/gems
    # and moved gems out out stage/opt to stage/gems. The stage/gems will be
    # lazy loaded into /tmp/jets and symlinked over. Example:
    #
    #   /opt/ruby/gems/2.5.0/gems/hello-1.2.3 -> /tmp/ruby/gems/2.5.0/gems/hello-1.2.3
    #
    def create
      display_sizes

      lazy_load_gems = !within_lambda_limit?
      if lazy_load_gems
        say "Code size + gems layer over lambda limit. Limit: #{LAMBDA_SIZE_LIMIT}MB Total size: #{megabytes(total_size)}"
        symlink_tmp_gems
      else
        say "Code size + gems layer is within the limit"
      end

      display_sizes

      unless within_lambda_limit?
        say "Cannot fit code into AWS Lambda code size limit even after lazying loading all the gems.".colorize(:red)
        say "The reduced total size after lazy loading gems is: #{megabytes(total_size)}. The Lambda limit is #{LAMBDA_SIZE_LIMIT}MB"
        say "Please reduce the size of your code."
        halt
      end

      symlink_vendor_gems
    end

    # For spec expectation
    def halt; exit 1; end

    # Complex logic. We symlink gems to /tmp folder that is lazy loaded.
    #
    # For bundler/gems (git source gems). Always move them to lazy loaded first. Since they are generally pretty big.
    #
    #   /opt/ruby/gems/2.5.0/bundler -> /tmp/ruby/gems/2.5.0/bundler
    #
    # For regular gems:
    #
    #   /opt/ruby/gems/2.5.0/gems/hello-1.2.3 -> /opt/ruby/gems/2.5.0/gems/hello-1.2.3
    #   /opt/ruby/gems/2.5.0/specifications/hello-1.2.3.gemspec -> /opt/ruby/gems/2.5.0/gems/specifications/hello-1.2.3.gemspec
    #
    # For common folders leave as is
    #
    #   /opt/ruby/gems/2.5.0/bin
    #   /opt/ruby/gems/2.5.0/build_info
    #   /opt/ruby/gems/2.5.0/doc
    #   /opt/ruby/gems/2.5.0/extensions
    #
    def symlink_tmp_gems
      until within_lambda_limit? || @done_moving do
        move_gems
        @done_moving = done_moving?
      end
    end

    def move_gems
      move_bundler_gems
      move_normal_gem
    end

    def move_normal_gem
      gem_path = Dir.glob("#{stage_area}/opt/ruby/gems/2.5.0/gems/*").sort.find do |path|
        !File.symlink?(path)
      end
      return unless gem_path
      gem_name = File.basename(gem_path)
      move_and_symlink("gems/#{gem_name}")
      move_and_symlink("specifications/#{gem_name}.gemspec")
    end

    def done_moving?
      ruby_folder = "#{stage_area}/opt/ruby/gems/2.5.0"

      bundler_check = !File.exist?("#{ruby_folder}/bundler") ||
                      File.symlink?("#{ruby_folder}/bundler")

      all_symlinks_check = all_symlinks?("#{ruby_folder}/gems") &&
                           all_symlinks?("#{ruby_folder}/specifications")

      bundler_check && all_symlinks_check
    end

    def all_symlinks?(folder)
      Dir.glob("#{folder}/*").reject { |p| File.symlink?(p) }.empty?
    end

    # Gem specifically under opt/ruby/gems/2.5.0/bundler
    def move_bundler_gems
      bundler_path = "#{stage_area}/opt/ruby/gems/2.5.0/bundler"
      return unless File.exist?(bundler_path)
      return if File.symlink?(bundler_path)
      move_and_symlink("bundler")
    end

    # Moves the folder in /opt to /gems and symlinks to it from /opt to /gems.
    #
    # Parameter: relative_path within the ruby folder. IE: 2.5.0
    #
    # Example:
    #
    #   move_and_symlink("bundler")
    #   =>
    #   /opt/ruby/gems/2.5.0/bundler -> gems/2.5.0/bundler
    #
    def move_and_symlink(path)
      src = "#{stage_area}/opt/ruby/gems/2.5.0/#{path}"
      dest = "#{stage_area}/gems/2.5.0/#{path}"
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.mv(src, dest)
      # say "ln -sf #{dest} #{src}" # uncomment to see and debug
      FileUtils.ln_sf(dest, src)
    end

    def within_lambda_limit?
      total_size < LAMBDA_SIZE_LIMIT * 1024 # 120MB
    end

    def total_size
      code_size = compute_size("#{stage_area}/code")
      opt_size = compute_size("#{stage_area}/opt")
      opt_size + code_size # total_size
    end

    # Simple logic: vendor/bundle/ruby/2.5.0 -> /opt/ruby/gems/2.5.0
    def symlink_vendor_gems
      ruby_folder = Jets::Gems.ruby_folder
      dest = "#{code_area}/vendor/bundle/ruby/#{ruby_folder}"
      FileUtils.mkdir_p(File.dirname(dest))
      say "ln -sf /opt/ruby/gems/#{ruby_folder} #{dest}"
      FileUtils.ln_sf("/opt/ruby/gems/#{ruby_folder}", dest)
    end

    def display_sizes
      code_size = compute_size("#{stage_area}/code")
      opt_size = compute_size("#{stage_area}/opt")
      total_size = opt_size + code_size
      say "code: #{megabytes(code_size)}"
      say "opt: #{megabytes(opt_size)}"
      say "total: #{megabytes(total_size)}"
      say "remaining: #{megabytes(LAMBDA_SIZE_LIMIT * 1024 - total_size)}"
      sh "du -csh #{stage_area}/*" unless ENV['TEST']
    end

    def compute_size(path)
      out = `du -s #{path}`
      out.split(' ').first.to_i # bytes
    end

    def megabytes(bytes)
      n = bytes / 1024.0
      sprintf('%.1f', n) + 'MB'
    end

    def say(message)
      puts message unless ENV['TEST']
    end
  end
end
