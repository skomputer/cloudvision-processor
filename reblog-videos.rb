gem 'simple_oauth', '=0.2.0'
require 'tumblr_client'
require 'yaml'

print "----- #{Time.now.to_s} -----\n"

PATH = File.expand_path(File.dirname(__FILE__))
CONFIG = YAML.load_file(PATH + '/config.yml')

blogs = CONFIG['tumblr']['blogs']

blog1 = blogs.first
blog2 = blogs.last
auth1 = Hash[blog1['auth'].map { |k, v| [k.to_sym, v] }]
auth2 = Hash[blog2['auth'].map { |k, v| [k.to_sym, v] }]

t1 = Tumblr::Client.new(auth1)
t2 = Tumblr::Client.new(auth2)

posts = t2.posts(blog2['url'], limit: 20, notes_info: true)['posts'].sort { |p| p['timestamp'] }
posts.each do |post|
  reblogged = post['notes'] and post['notes'].find { |n| n['blog_name'] == blog1['name'] and n['type'] == 'reblog' }

  print "#{blog2['name']} video #{post['id']} #{reblogged ? 'ALREADY' : 'NOT'} reblogged\n"

  if reblogged == nil
    reblog = t1.reblog(blog1['url'], id: post['id'], reblog_key: post['reblog_key'], tags: post['tags'].join(',') )
    print "---> REBLOGGED by #{blog1['name']}: #{reblog['id']}\n"
  end
end
