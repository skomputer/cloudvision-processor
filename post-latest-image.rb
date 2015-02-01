require 'fileutils'

PATH = File.expand_path(File.dirname(__FILE__))

new_images = Dir[PATH + '/incoming/*'].sort_by { |f| File.mtime(f) }
exit unless new_images.count > 1

FileUtils.cp(new_images[-2], PATH + '/public/latest.jpg')