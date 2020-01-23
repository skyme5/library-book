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

class String
  def truncate(limit = 40)
    return self if length <= 40

    words = split

    chunk_length = words.length.even? ? words.length / 2 : (words.length + 1) / 2
    words = words.each_slice(chunk_length).to_a
    prefix = words.first
    suffix = words.last

    length = 0
    prefix.select! do |e|
      if length + e.length < limit
        length += e.length
        true
      else
        false
      end
    end

    length = 0
    suffix.reverse!.select!  do |e|
      if length + e.length < limit
        length += e.length
        true
      else
        false
      end
    end

    [prefix, '...', suffix.reverse].flatten.join(' ')
  end
end

$DEBUG = true
$LOG = TTY::Logger.new

$book_list = []

$BOOK_DIR = [
  '/media/drive/e/Documents',
  '/media/drive/z/Books'
]

$SKIPFILES = ['.', '..']

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

def sendRequest(data)
  $LOG.info("submitting #{data['filepath']}")
  uri = URI.parse('http://127.0.0.1:3232/api/v2/book')
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.path)
  request.add_field('Content-Type', 'application/json; charset=utf-8')
  request.body = data.to_json
  response = http.request(request)
  responseText = response.body
  $LOG.info(responseText.force_encoding('UTF-8'))
  responseText.include?('{"success":true}') || responseText.include?('"code":11000')
end

def check_isbn(isbn_str)
  isbn = Lisbn.new(isbn_str)
  if isbn.valid?
    {
      is_valid: isbn.valid?,
      isbn10: isbn.isbn10,
      isbn13: isbn.isbn13,
      isbn: isbn.isbn,
      isbn_pretty: Lisbn.new(isbn.isbn13).isbn_with_dash
    }
  else
    {
      is_valid: isbn.valid?
    }
  end
end

def capture_fn(filename, extract = false)
  return $REGEXP === filename unless extract

  $REGEXP.match(filename)['isbn']
end

def path_truncate(path)
  parts = path.split(%r{/|\\})
  if parts.length > 3
    return [parts[0..2], '...', parts[-1].truncate].flatten.join('/')
  end

  path
end

def generate_list(path)
  $LOG.info "scanning => #{path_truncate(path)}" if $DEBUG
  Dir.entries(path, encoding: 'UTF-8').each do |file|
    next if $SKIPFILES.include? file

    filepath = File.join(path, file)
    if File.directory?(filepath)
      generate_list(filepath)
    else
      if $CAPTUREFILE.include? File.extname(filepath).downcase
        $book_list << filepath if capture_fn(filepath)
      end
    end
  end
end

$BOOK_DIR.each do |path|
  generate_list(path)
end

$history = File.exist?('history.txt') ? File.read('history.txt').split("\n") : []

$book_list.map! do |filepath|
  isbn = capture_fn(filepath, extract = true)
  {
    filepath: filepath,
    isbn: check_isbn(isbn)
  }
end.select! do |e|
  e[:isbn][:is_valid] && !$history.include?(e[:isbn][:isbn13])
end.map! do |book|
  filepath = book[:filepath]
  $LOG.debug "processing => #{filepath}" if $DEBUG

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
    title: basename
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

  cover_dst = "/media/drive/d/Server/nginx/html/images/cover/book/#{data[:isbn_pretty]}.jpg"
  if File.exist?(cover_file) && !File.exist?(cover_dst)
    FileUtils.cp(cover_file, cover_dst)
  end

  data
end

begin
  $book_list.each do |book|
    puts book[:filepath]
    $history << book[:id] if sendRequest(book)
  end
  out = File.open('history.txt', 'w')
  out.print $history.join("\n")
  out.close
rescue StandardError => e
  print e.backtrace.join("\n")
  out = File.open('history.txt', 'w')
  out.print $history.join("\n")
  out.close
end
