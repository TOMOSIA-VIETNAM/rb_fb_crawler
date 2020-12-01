class Post
  attr_accessor :content, :images
  
  def initialize(content, images)
    @content = content
    @images = images
  end
end
