require './models/album.rb'
require './models/album_collection.rb'
require './models/post.rb'
require './models/post_collection.rb'
require 'parallel'
require 'httparty'

options = { js_errors: false }
Capybara.javascript_driver = :poltergeist
Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, options)
end


class AnalyzeDomService
  include GetInfosHelper

  attr_accessor :title_page, :desc_page, :dom, :page, :posts, :address, :phone

  def initialize(page)
    @page = page
    @dom = Nokogiri::HTML.parse(page.html)
    
  end

  def call
    fetch_meta
    fetch_posts
    # fetch_albums
  end

  private

  def fetch_meta
    meta = dom.css('meta')
    unless meta.empty?
      @title_page = dom.title
      @desc_page = attribute meta[2] 
    end
    @address = page.find('._2nx_._3jb8._3jbj._2rgt._1j-f._2rgt').text if page.has_css?('._2nx_._3jb8._3jbj._2rgt._1j-f._2rgt')
    @phone = dom.css('._7-v._9_7._2rgt._1j-f._2rgt').css('._59k._2rgt._1j-f._2rgt')[1].text
  end

  def fetch_posts
    output 'fetching posts'

    records = []
    all_posts = dom.css('.story_body_container')
    puts dom.css('.story_body_container').count
    return records if all_posts.empty?
  
    Parallel.map_with_index(all_posts, in_threads: 20) do |data, i|
      post = Post.new(fetch_content(data), fetch_post_images(data))
      records << post
    end
    output 'fetch posts success'
    @posts = PostCollection.new(records)
  end

  def fetch_content data
    data.css('._5msi').text
  end

  def fetch_post_images data
    all_images = data.css('._27x0').css('a')
    return [] if all_images.empty?

    images = []
    Parallel.map(all_images, in_threads: 10) do |url_image|
      next unless URI.extract(url_image.attributes['href'].value, %w[http https]).empty?
      next unless url_image.attributes['href'].value.include?('/')

      post_image_path = "https://m.facebook.com#{url_image.attributes['href'].value}"
      puts post_image_path
      begin
        page_image = HTTParty.get(post_image_path)
        next unless page_image

        image_dom = Nokogiri::HTML.parse(page_image)
        folder_image = image_dom.css('.atb').css('a')[2]

        next unless folder_image
        images << folder_image.attributes['href'].value
      rescue URI::InvalidURIError, HTTParty::RedirectionTooDeep
        next
      end
    end
    images
  end

  def fetch_albums
    click_albums
    output 'fetching albums'
    dom_albums = Nokogiri::HTML.parse(page.html)
    dom_all_albums = dom_albums.css('#pages_msite_body_contents').css('._55x2 > div')
    return unless dom_all_albums
    
    records = []
    Parallel.map(dom_all_albums, in_threads: 20) do |data|
      title = data.css('._52jh').text
      puts title

      url_path = data.css('a')[0].attributes['href'].value
      next unless URI.extract(url_path, %w[http https]).empty? || url_path.include?('/')
      next unless url_path.include?('/')
      
      url_album_image = "https://www.facebook.com#{url_path}"
      begin
        dom_album = ConnectService.connect_page url_album_image
      rescue Capybara::Poltergeist::StatusFailError, Capybara::Poltergeist::TimeoutError
        next
      end
      next unless dom_album

      scroll_page dom_album

      response_album = Nokogiri::HTML.parse(dom_album.html)
      all_images = response_album.css('#pages_msite_body_contents').css('._55wo').css('._5v64')
      next unless all_images

      image_albums = []
      Parallel.map(all_images, in_threads: 20) do |image|
        next unless image.css('a')

        url_image_path = "https://www.facebook.com#{image.css('a')[0].attributes['href'].value}"
        page_image = ConnectService.connect_page url_image_path
        image_dom = Nokogiri::HTML.parse(page_image.html)
        next unless image_dom || image_dom.css('.atb').css('a')[1]
        
        begin
          image_albums << image_dom.css('.atb').css('a')[1].attributes['href'].value
        rescue NoMethodError
          next
        end
        page_image.driver.quit
      end
      album = Album.new(title, image_albums)
      records << album
      dom_album.driver.quit
    end
    @albums = AlbumCollection.new(records)
    output 'fetch albums success'
  end

  def scroll_page dom_album
    output 'scrolling album'
    loop do
      dom_album.execute_script 'window.scrollBy(0, 1000);'
      sleep 1 
      break unless dom_album.has_css?('#m_more_photos')
    end
    output 'scroll album success'
  end

  def click_albums
    output 'Redirecting to all albums'
    page.click_link('Ảnh')
    return unless page.has_css?('._1s09')
    
    page.find('._1s09').click 
    page.find('.primary').trigger('click') if page.has_css?('.primary')
    output 'Redirect to all albums'
    page
  end
end
