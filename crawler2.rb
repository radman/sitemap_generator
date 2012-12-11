require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'builder'
require 'logger'

class Crawler2
  def initialize
    @output = $stdout
    @logger = Logger.new('crawl.log')
  end

  def log(msg = "")
    @logger.info(msg)
    puts msg
  end
 
  # Options allowed
  # - max_pages (number)
  # - generate_sitemap (file name)
  # - crawl_rate (number of seconds between requests)
  # - include_ssl (false by default; if true, crawls https pages)
  def crawl(seed, options = {})
    f = Frontier.new(seed, :max_allowed_to_pass => options[:max_pages], :allow_ssl => options[:include_ssl], :filter => options[:filter])
    bad_uris = []

    while crawl_uri = f.dequeue
      uri = crawl_uri.uri
      parent_uri = crawl_uri.parent_uri
      
      start_time = Time.now
      page_links = fetch_page_links(uri)
      duration = Time.now - start_time

      if page_links
        page_links.each do |link|
          begin
            result = f.process link, :parent_uri => uri
            #if !result
            #  puts "\x1B[33mProcessed #{link}: #{result}\x1B[0m"
            #end
          rescue Exception => ex
            log "[An unknown error occurred]"
            raise
          end
        end
        log "#{f.passed.count} - #{parent_uri || 'root'} -> #{uri} (#{sprintf('%.2f',duration)} sec; queued: #{f.count})"
      else
        bad_uris << uri
        log "#{f.passed.count} - #{parent_uri || 'root'} -> #{uri} (#{sprintf('%.2f',duration)} sec; queued: #{f.count}) [Error fetching links]"
      end

      sleep options[:crawl_rate] || 1
    end

    log "Done."

    generate_sitemap(options[:generate_sitemap], f.passed - bad_uris) if options[:generate_sitemap]
  end

  private


  # PRE: uri is an instance of URI
  # POST: returns an array of strings
  # (Does not guarantee validity of links) 
  def fetch_page_links(uri)
    Nokogiri::HTML(open(uri).read).css("a").map do |link|
      if (href = link.attr("href"))
        href
      end
    end.compact
  rescue Exception => ex
    log "Unhandled exception while fetching links of #{uri}"
    log "Error fetching links of #{uri}"
    log ex.class
    log ex.message
    return []
  end

  def generate_sitemap(file, uri_list)
    xml_str = ""
    xml = Builder::XmlMarkup.new(:target => xml_str, :indent => 2)
 
    xml.instruct!
    xml.urlset(:xmlns=>'http://www.sitemaps.org/schemas/sitemap/0.9') {
      uri_list.compact.collect(&:uri).each do |uri|
        unless uri.nil?
          xml.url {
            xml.loc(uri.to_s)
            xml.lastmod(Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S+00:00"))
            xml.changefreq('weekly')
           }
         end
      end
    }
 
    save_file(file, xml_str)
  end

  # Saves the xml file to disc. 
  def save_file(file, xml)    
    File.open(file, "w+") do |f|
      gz = Zlib::GzipWriter.new(f)
      gz.write(xml)  
      gz.close
    end     
  end

end

class Frontier
  attr_reader :queue
  attr_reader :passed
  
  # Options allowed
  # - max_allowed_to_pass
  def initialize(seed, options = {})
    @options = options
    @seed = seed
    @filter = options[:filter]
    @queue = [ CrawlUri.new(seed, nil) ]
    @passed = Array.new
    @ignored = Array.new

    @output = $stdout
    @logger = Logger.new('crawl.log')
  end

  def log(msg = "")
    @logger.info(msg)
  end

  # Returns true if the uri was successfully added to the queue; false otherwise
  # PRE: uri is an instance of Uri
  # POST: queues up an instance of CrawlUri
  def process(uri, options = {})
    normalized_uri = CrawlUri.new(normalize_uri(uri, options[:parent_uri]), options[:parent_uri])
    if normalized_uri.uri && 
       ((@filter && normalized_uri.uri =~ /#{@filter}/) || normalized_uri.uri =~ /^#{@seed}/) && 
       !@passed.include?(normalized_uri) &&
       !@queue.include?(normalized_uri)
      if normalized_uri.uri =~ /^https/
        log "\x1B[33m- queueing #{normalized_uri.uri}\x1B[0m"
      else
        log "- queueing #{normalized_uri.uri}"
      end

      @queue.push(normalized_uri)
      return true
    else
      return false
    end
  rescue Exception => e
    log "Error while processing uri='#{uri}', parent_uri='#{options[:parent_uri] ? options[:parent_uri] : 'NIL'}' (SKIPPING)"
    #raise
    return false
  end

  def dequeue
    return nil if @options[:max_allowed_to_pass] && @passed.size == @options[:max_allowed_to_pass]
    @passed << @queue.shift
    return @passed.last
  end

  def count
    @queue.count
  end

  private

  # NOTE: Assumes parent_uri is already normalized
  def normalize_uri(uri, parent_uri = nil)
    return nil if uri.nil?

    normalized = uri.is_a?(URI) ? uri : URI.parse(uri)

    if normalized.relative?
      return nil if !parent_uri
      normalized = URI.parse(parent_uri).merge(normalized)
    end

    scheme = normalized.scheme
    allowed_schemes = [ 'http' ]
    allowed_schemes << 'https' if @options[:allow_ssl]
    return nil unless allowed_schemes.include?(scheme)

    normalized = normalized.normalize

    query_string = normalized.select(:query)[0]
    normalized = normalized.select(:host, :path).join
    normalized += "?#{query_string}" if query_string

    normalized = CGI.unescape(normalized)
    normalized = "#{scheme}://#{normalized}"
    normalized = normalized.split('#').first
    
    return normalized
  end
end

class CrawlUri
  attr_reader :uri
  attr_reader :parent_uri

  def initialize(uri, parent_uri)
    @uri = uri
    @parent_uri = parent_uri
  end

  def ==(o)
    self.uri == o.uri
  end
end
