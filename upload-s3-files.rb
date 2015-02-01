require 'aws/s3'
require 'yaml'

PATH = File.expand_path(File.dirname(__FILE__))
CONFIG = YAML.load_file(PATH + '/config.yml')

AWS::S3::Base.establish_connection!(
  :access_key_id     => CONFIG['s3']['access_key_id'], 
  :secret_access_key => CONFIG['s3']['secret_access_key']
)

files = Dir[PATH + '/videos/*']
files.each do |file|
  base = File.basename(file)
  s3_path = "videos/#{base}"

  if AWS::S3::S3Object.exists?(s3_path, CONFIG['s3']['bucket'])
    print "skipping #{file}; already exists on S3\n"
  else
    AWS::S3::S3Object.store(
      s3_path, 
      open(PATH + "/videos/#{base}"), 
      CONFIG['s3']['bucket'], 
      :access => :public_read
    )
    print "uploaded #{file} to S3\n"
  end
end