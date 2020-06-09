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

def capture_fn(filename)
  regexp = /_\[[\[\]\s]*\]\.\w+$/
  return regexp === filename
end

def generate_list(path)
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

$book_list.each do |e|
  puts e
end
