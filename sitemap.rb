require 'rubygems'
require 'yaml'
require './crawler2'

config = YAML.load_file(File.join(File.expand_path(File.dirname(__FILE__), 'config.yml')))

crawler = Crawler2.new

#crawler.crawl config['site'], :max_pages => 20, :generate_sitemap => "./sitemap.xml.gz"
crawler.crawl config['site'], :generate_sitemap => "./sitemap.xml.gz", :filter => config['filter'], :crawl_rate => 0.1

