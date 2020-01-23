class String
  def truncate(limit=40)
    words = self.split

    chunk_length = words.length % 2 == 0 ? words.length/2 : (words.length+1)/2
    words = words.each_slice(chunk_length).to_a
    prefix = words.first
    suffix = words.last

    length = 0
    prefix.select!{
      |e|
      if length + e.length < limit
        length = length + e.length
        true
      else
        false
      end
    }

    length = 0
    suffix.reverse!.select!{
      |e|
      if length + e.length < limit
        length = length + e.length
        true
      else
        false
      end
    }

    return [prefix, "...", suffix.reverse].flatten.join(" ")
  end
end

puts "(Geld – Banken – Börsen) Peter Lückoff - Mutual Fund Performance and Performance Persistence-Gabler (2011)_9783834927804.pdf".truncate
