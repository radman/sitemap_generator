require 'rubygems'
require 'anemone'
require 'sitemap_generator'
require 'yaml'

config = YAML.load_file(File.join(File.expand_path(File.dirname(__FILE__), 'config.yml')))

pages = []

Anemone.crawl(config['site']) do |anemone|
  anemone.on_every_page do |page|
    if !page.visited
      pages << page
      puts page.url
    end
  end

  anemone.after_crawl do |pages|
  end
end

SitemapGenerator::Sitemap.default_host = config['site']
SitemapGenerator::Sitemap.create_index = false
SitemapGenerator::Sitemap.create  do
  pages.each do |page|
    add page.url.path unless page.url.path == "/"
  end
end

