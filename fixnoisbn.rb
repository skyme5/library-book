#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'lisbn'

noisbn_tmp = 'noisbn.tmp'

`echo > #{noisbn_tmp}`

['Z:/LIBGEN'].each do |e|
	`find #{e} >> #{__dir__}/#{noisbn_tmp}`
end

list = File.read(__dir__ + '/' + noisbn_tmp).split("\n").select do |e|
	e.match(/\[[\sNA]*\]\.\w+/)
end

json = list.select { |e| File.extname(e) == '.json' }

out = File.open('fixisbn.bat', 'w')
json.each do |json_file|
  data = JSON.parse(File.read(json_file))
  isbn = data['data']['json']['identifier']
  puts "NO ISBN => #{json_file}" if isbn.nil?
  next if isbn.nil?

  # isbn = isbn.split(/[;,]+|\s+[ISBN\-13\(\):]\s+|\s+/).select { |e| Lisbn.new(e).valid? }
  isbn = isbn.scan(/[\d\-X]+/)
             .map { |e| e.gsub('-', '') }
             .select { |e| Lisbn.new(e).valid? }
  puts "Invalid ISBN => #{json_file}" if isbn.empty?
  puts data['data']['json']['identifier'] if isbn.empty?
  next if isbn.empty?

  isbn = Lisbn.new(isbn.first).isbn13

  srcname = File.basename(json_file, '.json')
  dstname = srcname.gsub('[]', "[#{isbn}]")

  files = list.select { |e| e.include?(srcname) }
  files.each do |src|
    ext = File.extname(src)
    out.puts "rename \"#{src}\" \"#{dstname}#{ext}\"".gsub('/', '\\')
  end
end
out.close
