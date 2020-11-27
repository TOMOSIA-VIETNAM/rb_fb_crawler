module GetInfosHelper
  def attribute value
    return unless value

    value.attributes['content'].value
  end

  def output log
    puts "-----#{log}------"
  end
end
