require 'yaml'
require 'tumblr_client'
require 'aws/s3'
require 'capybara'
require 'capybara/webkit'
require 'faraday'
require 'json'
require 'youtube_it'
require 'twitter'

PATH = File.expand_path(File.dirname(__FILE__))
CONFIG = YAML.load_file(PATH + '/config.yml')

print "----- #{Time.now.to_s} -----\n"

last_image = File.read(PATH + '/last_image').strip.to_i
new_images = Dir[PATH + '/incoming/*'].sort_by { |f| File.mtime(f) }.keep_if { |f| f[/\d{4,}/].to_i > last_image }.sort.take(1200)
exit unless new_images.count > 0

File.open(PATH + '/new-files.txt', 'w') do |file|
  file << new_images.join("\n")
end

start_time = (Time.now - 2 * 60 * 60).strftime('%H:%M')
start_date = (Time.now - 2 * 60 * 60).strftime('%d %b %Y')
end_time = Time.now.strftime('%H:%M')
end_date = Time.now.strftime('%d %b %Y')
caption = (start_date == end_date) ? "#{start_time}-#{end_time}, #{end_date}" : "#{start_time}, #{start_date} - #{end_time}, #{end_date}"

date = `date +'%m%d%y-%H%M%S'`.strip

video_path = PATH + "/videos/video-#{date}.avi"
video_files_path = PATH + "/videos/video-#{date}-files.txt"
system("mencoder -nosound -ovc lavc -lavcopts vcodec=mpeg4:vbitrate=16000000 -o #{video_path} -mf type=jpeg:fps=24 mf://@#{PATH}/new-files.txt -vf scale=1920:1440")

File.open(video_files_path, 'w') do |file|
  file << new_images.map{ |f| f.split("/").last }.join("\n")
end

File.open(PATH + '/last_image', 'w') do |file|
  file << new_images.last[/\d+/].to_i
end


# POST TO TUMBLR

url = nil
num_posts = nil
t = nil

CONFIG['tumblr']['blogs'].each do |blog|
  auth = Hash[blog['auth'].map { |k, v| [k.to_sym, v] }]
  t = Tumblr::Client.new(auth)
  url = blog['url']
  num_posts = t.posts(url, type: :video, limit: 20, reblog_info: true)['posts'].keep_if { |p| Time.at(p['timestamp']) >= Time.now - 60 * 60 * 24 }.keep_if { |p| [blog['name'], nil].include? p['reblogged_from_name'] }.count
  
  if num_posts < 6
    break
  else
    print "skipping #{url}: already posted #{num_posts} videos today\n"
  end
end

print "posting video #{video_path} to #{url}...\n"
tags = CONFIG['tumblr']['tags']
results = t.video(url, data: video_path, caption: caption, tags: tags)
print "\n" + results.to_s + "\n"

unless results['id']
  # print "ERROR posting video to #{url}\n"
  # print "quiting...\n"
  # exit
end


# POST TO YOUTUBE

google = CONFIG['google']
client_id = google['oauth']['client_id']
client_secret = google['oauth']['client_secret']
api_key = google['oauth']['api_key']
redirect_uri = google['oauth']['redirect_uri']
url = "https://accounts.google.com/o/oauth2/auth?client_id=#{client_id}&redirect_uri=#{redirect_uri}&scope=https://gdata.youtube.com&response_type=code&approval_prompt=force&access_type=offline"

session = Capybara::Session.new(:webkit)
session.visit(url)
session.fill_in('Email', with: google['email'])
session.fill_in('Passwd', with: google['password'])
session.click_button('Sign in')
session.click_link(google['app_name'])
session.click_button('Accept')
oauth_code = session.current_url.split("code=").last

conn = Faraday.new(:url => 'https://accounts.google.com',:ssl => {:verify => false}) do |faraday|
  faraday.request  :url_encoded
  faraday.response :logger
  faraday.adapter  Faraday.default_adapter
end

result = conn.post('/o/oauth2/token', {
  'code' => oauth_code,
  'client_id' => client_id,
  'client_secret' => client_secret,
  'redirect_uri' => redirect_uri,
  'grant_type' => 'authorization_code'
})

access_token = JSON.parse(result.body)['access_token']
refresh_token = JSON.parse(result.body)['refresh_token']

client = YouTubeIt::OAuth2Client.new(
  client_access_token: access_token, 
  client_refresh_token: refresh_token, 
  client_id: client_id, 
  client_secret: client_secret,
  dev_key: api_key
)

result = client.video_upload(
  File.open(video_path), 
  { 
    title: google['post']['title_prefix'] + caption,
    description: google['post']['description'], 
    category: google['post']['category'],
    keywords: google['post']['tags'].split(',')
  }
)


# POST YOUTUBE LINK TO TWITTER

if result.respond_to?(:unique_id) and result.unique_id
  twitter = Twitter::REST::Client.new do |config|
    config.consumer_key        = CONFIG['twitter']['oauth']['consumer_key']
    config.consumer_secret     = CONFIG['twitter']['oauth']['consumer_secret']
    config.access_token        = CONFIG['twitter']['oauth']['access_token']
    config.access_token_secret = CONFIG['twitter']['oauth']['access_token_secret']
  end

  tweet = twitter.update("#{result.title} http://youtube.com/watch?v=#{result.unique_id}")
  print "tweeted #{tweet.uri}\n"
end

AWS::S3::Base.establish_connection!(
  :access_key_id     => CONFIG['s3']['access_key_id'], 
  :secret_access_key => CONFIG['s3']['secret_access_key']
)

AWS::S3::S3Object.store(
  "videos/video-#{date}.avi", 
  open(video_path), 
  CONFIG['s3']['bucket'], 
  :access => :public_read
)

AWS::S3::S3Object.store(
  "videos/video-#{date}-files.txt", 
  open(video_files_path), 
  CONFIG['s3']['bucket'], 
  :access => :public_read
)

File.delete(*new_images)
File.delete(video_path)
File.delete(video_files_path)