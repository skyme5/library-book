#!/usr/bin/ruby
# frozen_string_literal: true

# @Author: Aakash Gajjar
# @Date:   2019-07-03 17:41:34
# @Last Modified by:   Sky
# @Last Modified time: 2019-10-08 19:58:10

require 'pathname'
require 'digest'
require 'fileutils'
require 'json'
require 'uri'
require 'net/http'
require 'net/https'

require 'lisbn'
require 'tty-logger'

$DEBUG = true
$LOG = TTY::Logger.new

$book_list = []

$BOOK_DIR = if ARGV.empty?
  [
    'z:/Books'
  ]
else
  ARGV
end

$SKIPFILES = ['.', '..']
$EXCLUDE_REGEXP = /Manga..*Manga.*|MBSc|SanDisc|Light Novel \- WEB/

$CAPTUREFILE = [
  '.azw',
  '.azw3',
  '.djv',
  '.djvu',
  '.epub',
  '.mobi',
  '.pdf'
]

$REGEXP = /_\[?(?<isbn>[0-9 \-]{10,})\]?\.\w+$/

$print_last_length = 0

def single_line_print(line, index=0, length=0)
  str = ""
  if index.positive? && length.positive?
    str = "#{(index*100.0/length).round(2)}%, "
  end
  str += line

  if str.length > $print_last_length
    $print_last_length = str.length
  else
    str = str.ljust($print_last_length)
  end
  print str + "\r"
end

def send_request(data)
  uri = URI.parse('http://127.0.0.1:3232/api/v2/book')
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.path)
  request.add_field('Content-Type', 'application/json; charset=utf-8')
  request.body = data.to_json
  response = http.request(request)
  response_body = response.body
  # $LOG.info(response_body.force_encoding('UTF-8'))
  response_body.include?('{"success":true}') || response_body.include?('"code":11000')
end

def check_isbn(isbn_str, filepath)
  isbn = Lisbn.new(isbn_str)
  if isbn.valid?
    { is_valid: isbn.valid?,
      isbn10: isbn.isbn10,
      isbn13: isbn.isbn13,
      isbn: isbn.isbn,
      isbn_pretty: Lisbn.new(isbn.isbn13).isbn_with_dash }
  else
    puts "Invalid ISBN: #{filepath}"
    { is_valid: isbn.valid? }
  end
end

def capture_fn(filename, extract = false)
  regexp = /_\[?(?<isbn>[0-9 \-]{10,})\]?\.\w+$/
  return regexp === filename unless extract

  regexp.match(filename)['isbn']
end

def generate_list(path)
  single_line_print(path)
  Dir.entries(path, encoding: 'UTF-8').each do |file|
    next if $SKIPFILES.include? file

    filepath = File.join(path, file)
    if File.directory?(filepath)
      generate_list(filepath) unless $EXCLUDE_REGEXP.match(filepath)
    else
      if $CAPTUREFILE.include? File.extname(filepath).downcase
        $book_list << filepath if capture_fn(filepath)
      end
    end
  end
end

$BOOK_DIR.each do |path|
  generate_list(path) if File.directory?(path)
end

$history = File.exist?(__dir__ + '/archive.txt') ? File.read(__dir__ + '/archive.txt').split("\n") : []

$book_list.map! do |filepath|
  isbn = capture_fn(filepath, extract = true)
  {
    filepath: filepath,
    isbn: check_isbn(isbn, filepath)
  }
end.select! do |e|
  e[:isbn][:is_valid] && !$history.include?(e[:isbn][:isbn13])
end.map! do |book|
  filepath = book[:filepath]
  puts "processing => #{filepath}" if $DEBUG

  directory = File.dirname(filepath)
  filename = File.basename(filepath)
  extname = File.extname(filename)
  basename = File.basename(filename, extname)

  cover_file = File.join(directory, basename + '.jpg')
  libgen_file = File.join(directory, basename + '.json')
  bibtex_file = File.join(directory, basename + '.bib')

  data = {
    id: book[:isbn][:isbn13].to_i,
    filepath: book[:filepath],
    isbn10: book[:isbn][:isbn10],
    isbn13: book[:isbn][:isbn13],
    isbn_pretty: book[:isbn][:isbn_pretty],
    md5: Digest::MD5.file(book[:filepath]).hexdigest,
    title: basename,
    created_at: 1000 * File.mtime(book[:filepath]).to_i
  }

  data[:bibtex] = File.read(bibtex_file) if File.exist?(bibtex_file)
  if File.exist?(libgen_file)
    json = JSON.parse(File.read(libgen_file))
    json = json.first if json.class == Array
    if json.keys.include? 'data'
      data[:libgen] = json['data']['json']
      data[:title] = json['data']['json']['title']
      data[:authors] = json['data']['json']['author'].split(', ')
    elsif json.keys.include? 'coverurl'
      data[:libgen] = json
      data[:title] = json['title']
      data[:cover_url] = json['coverurl']
    end
  end

  cover_dst = ['h:/Server/nginx/html/images',
               'cover/book',
               "#{data[:isbn_pretty]}.jpg"].join("/")
  if File.exist?(cover_file) && !File.exist?(cover_dst)
    FileUtils.cp(cover_file, cover_dst)
  end

  data
end

$book_list.sort! { |a, b|
  a[:created_at] <=> b[:created_at]
}

begin
  $book_list.each do |book|
    puts book[:filepath]
    $history << book[:id] if send_request(book)
  end
  out = File.open(__dir__ + '/archive.txt', 'w')
  out.print $history.join("\n")
  out.close
rescue StandardError => e
  print e.backtrace.join("\n")
  out = File.open(__dir__ + '/archive.txt', 'w')
  out.print $history.join("\n")
  out.close
end
