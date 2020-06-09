#!/usr/bin/ruby
# frozen_string_literal: true

# @Author: Aakash Gajjar
# @Date:   2019-07-06 14:17:22
# @Last Modified by:   Sky
# @Last Modified time: 2019-07-13 00:31:04

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

$BOOK_DIR = [
  'z:/Books'
]

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

def single_line_print(line, index = 0, length = 0)
  str = ''
  if index.positive? && length.positive?
    str = "#{(index * 100.0 / length).round(2)}%, "
  end
  str += line

  if str.length > $print_last_length
    $print_last_length = str.length
  else
    str = str.ljust($print_last_length)
  end
  print str + "\r"
end

def saveJSON(data)
  data_json = data.to_json
  uri = URI.parse('http://127.0.0.1:3232')
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new('/api/v2/books/filepath/update')
  request.add_field('Content-Type', 'application/json; charset=utf-8')
  request.add_field('content-length', data_json.length)
  request.body = data_json
  response = http.request(request)
  $LOG.info "sending #{data_json.length} characters with #{data_json.bytesize}"
  $LOG.info response.body
  response.body.include? '{"success":true}'
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
  return [parts[0..2], '...', parts[-1]].flatten.join('/') if parts.length > 3

  path
end

def generate_list(path)
  single_line_print(path)
  $LOG.debug "scanning => #{path_truncate(path)}" if $DEBUG
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
  generate_list(path)
end

$book_list.map! do |filepath|
  isbn = capture_fn(filepath, extract = true)
  {
    filepath: filepath,
    isbn: check_isbn(isbn)
  }
end.select! do |e|
  e[:isbn][:is_valid]
end

$book_list.map! do |book|
  filepath = book[:filepath]
  data = {
    id: book[:isbn][:isbn13].to_i,
    filepath: book[:filepath].encode!(Encoding::UTF_8),
    created_at: 1000 * File.mtime(book[:filepath]).to_i
  }
  data
end

$book_list.each_slice(70) do |book|
  saveJSON(books: book)
end
