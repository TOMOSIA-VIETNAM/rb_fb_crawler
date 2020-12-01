require 'capybara' 
require 'retryable' 

module ConnectService
  def self.connect_page url
    Retryable.retryable(tries: 5, on: [Errno::EMFILE, Capybara::Poltergeist::TimeoutError, Timeout::Error]) do
      page = Capybara::Session.new(:poltergeist)
      page.driver.headers = { 'User-Agent' => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.120 Safari/537.36' }
      page.visit url
      page
    end
  end
end
