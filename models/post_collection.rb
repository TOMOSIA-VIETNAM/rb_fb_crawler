class PostCollection
  attr_accessor :records
  
  def initialize(records = [])
    @records = records
  end
end
