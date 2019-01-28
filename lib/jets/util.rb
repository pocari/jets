class Jets::Util
  class << self
    # Make sure that the result is a text.
    def normalize_result(result)
      JSON.dump(result)
    end

    def cp_r(src, dest)
      puts "Rsync is not installed or has not been detected. Rsync is required for `jets deploy`.".color(:red) unless rsync_installed?

      # Fix for https://github.com/tongueroo/jets/issues/122
      #
      # Using FileUtils.cp_r doesnt work if there are special files like socket files in the src dir.
      # Instead of using this hack https://bugs.ruby-lang.org/issues/10104
      # Using rsync to perform the copy.
      src.chop! if src.ends_with?('/')
      dest.chop! if dest.ends_with?('/')
      sh "rsync -a --links --no-specials --no-devices #{src}/ #{dest}/", quiet: true
    end

    def rsync_installed?
      system("type rsync > /dev/null 2>&1")
    end

    def sh(command, quiet: false)
      puts "=> #{command}" unless quiet
      system(command)
    end
  end
end
