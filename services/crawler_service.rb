require './modules/get_infos_helper.rb'
require './services/connect_service.rb'
require './services/analyze_dom_service.rb'
require './handle_errors/not_found_element_error.rb'


require 'pry'
require 'capybara/poltergeist'
require 'csv'
require 'down'
require 'retryable'

options = { js_errors: false }
Capybara.javascript_driver = :poltergeist
Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, options)
end


class CrawlerService

  include GetInfosHelper
  attr_reader :url, :page, :folder_page, :response

  def initialize(url)
    @url = url
    @page = ConnectService.connect_page(url)
  end

  def call
    return unless atc_login?

    atc_scroll_page
    act_crawl_info_page
    page_quit
  end

  private

  def atc_login?
    output 'Redirecting to Login'
    page.click_link('Đăng nhập', match: :first)
    page.fill_in 'email', with: ''
    page.fill_in 'pass', with: ''
    page.click_button 'Đăng nhập'
    if waiting_appear?('#launchpad')
      output 'Login success'
      true
    else 
      output 'Login not success'
      false
    end
  end

  def waiting_appear?(ele, tries: 5)
    found_element = false
    limit = 0
    loop do 
      found_element = true if page.has_css?(ele)
      break if found_element == true
      limit += 1
      sleep 1
      next if limit < tries
      
      begin
        raise NotFoundElementError.new('Login not success')
      rescue NotFoundElementError => e
        output e
        break
      end
    end
    found_element
  end

  def atc_scroll_page
    output 'Scrolling page'
    number = 0
    Retryable.retryable(tries: 3, on: Timeout::Error) do
      loop do
        page.execute_script 'window.scrollBy(0, 1000);'
        puts number
        sleep 1
        break unless page.has_css?('#see_more_cards_id')
      end
    end
    # 5.times do 
    #    page.execute_script 'window.scrollBy(0, 1000);'
    #   puts number
    #   sleep 1
    # end
    output 'Scroll page success'
  end

  def act_crawl_info_page
    @response = AnalyzeDomService.new(page)
    @response.call
    create_folder_page
    posts = download_posts
    # albums = download_albums
    generate_meta_csv posts
  end

  def generate_meta_csv posts
    CSV.open("#{folder_page}/prototype_crawler.csv", "wb") do |csv|
      csv << ['Title', 'Description', 'Address', 'Phone']
      csv << [response.title_page, response.desc_page, response.address, response.phone]
      csv << []
      csv << ['Posts']
      csv << ['ID', 'Content', 'Image Link Public', 'Image Folder']
      posts.each do |post|
        csv << post
      end
      # csv << []
      # csv << ['Albums']
      # csv << ['ID', 'Title', 'Image Link Public', 'Image Folder']
      # albums.each do |album|
      #   csv << album
      # end
    end
  end

  def format_path url
    "fanpage/#{url.split('/').last}" 
  end

  def create_folder_page
    @folder_page = format_path url
    output "Creating folder #{@folder_page}"
    FileUtils.rm_rf(@folder_page) if File.directory?(@folder_page)
    FileUtils.mkdir_p(@folder_page)
    output "Created folder #{@folder_page}"
    @folder_page
  end

  def download_posts
    output 'downloading posts'
    folder_posts = create_folder 'posts'
    all_posts = []
    return all_posts unless response.posts
    Parallel.map_with_index(response.posts.records.select {|post| post unless post.images.empty? }, in_threads: 20) do |post, i|
      csv = []
      folder_post = create_folder_post folder_posts, i
      ganerate_content_csv folder_post, post.content
      link_images = []
      Parallel.map(post.images, in_threads: 10) do |image|
        link_images << image
        download_image(folder_post, image)
      end
      csv << i+1
      csv << post.content
      csv << link_images.join(',')
      csv << folder_post
      all_posts << csv
    end
    output 'download albums posts'
    all_posts
  end

  def download_albums
    output 'downloading albums'
    folder_albums = create_folder 'albums'
    all_albums = []
    return all_albums unless response.albums

    Parallel.map_with_index(response.albums.records, in_threads: 20) do |album, i|
      next if album.title.empty? && album.images.empty?

      csv = []
      folder_album = create_folder_album folder_albums, album
      link_images = []
      path_images = []
      Parallel.map(album.images, in_threads: 20) do |image|
        link_images << image
        download_image(folder_album, image)
      end
      csv << i+1
      csv << album.title
      csv << link_images.join(',')
      csv << folder_album
      all_albums << csv
    end
    output 'download albums success'
    all_albums
  end

  def create_folder value
    folder_posts = "#{folder_page}/#{value}"
    puts "-----Creating #{folder_page}/#{value}------"
    FileUtils.mkdir_p(folder_posts)
    puts "-----Created #{folder_page}/#{value}------"
    folder_posts
  end

  def create_folder_post folder_posts, i
    folder_post = "#{folder_posts}/#{i+1}"
    FileUtils.mkdir_p folder_post
    folder_post
  end

  def create_folder_album folder_albums, album
    folder_album = "#{folder_albums}/#{album.title}"
    FileUtils.mkdir_p folder_album
    folder_album
  end

  def download_image folder, image
    tempfile = Down.download(image)
    FileUtils.mv(tempfile.path, "./#{folder}/#{tempfile.original_filename}")
  rescue Down::InvalidUrl, Down::ConnectionError
    puts 'image invalid'
  end

  def ganerate_content_csv folder_post, content
    CSV.open("#{folder_post}/content.csv", "wb") do |csv|
      csv << ['Content']
      csv << [content]
    end
  end

  def page_quit
    page.driver.quit
  end
end
