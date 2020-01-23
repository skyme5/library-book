#!/usr/bin/ruby
# frozen_string_literal: true

# @Author: Aakash Gajjar
# @Date:   2019-07-06 14:17:22
# @Last Modified by:   Sky
# @Last Modified time: 2019-07-26 19:04:12

require 'net/http'
require 'net/https'
require 'uri'
require 'open-uri'
require 'json'

require 'coloredlogger'

$LOG = ColoredLogger.new(STDOUT)

BOOK_API_FIELDS = %w[
  aich
  asin
  author
  bookmarked
  city
  cleaned
  color
  commentary
  coverurl
  crc32
  ddc
  doi
  dpi
  edition
  edonkey
  extension
  filesize
  generic
  googlebookid
  id
  identifier
  issn
  issue
  language
  lbc
  lcc
  library
  local
  locator
  md5
  openlibraryid
  orientation
  pages
  paginated
  periodical
  publisher
  scanned
  searchable
  series
  sha1
  timeadded
  timelastmodified
  title
  topic
  tth
  udc
  visible
  volumeinfo
  year
].freeze

def book_api_host
  'http://gen.lib.rus.ec'
end

def book_api_path_json(md5)
  '/json.php?ids=' + md5 + '&fields=' + BOOK_API_FIELDS.join(',')
end

def book_json_get(md5)
  $LOG.debug('API_FETCH_JSON', " => #{md5}")
  begin
    uri = URI.parse(book_api_host)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(book_api_path_json(md5))
    response = http.request(request)
    JSON.parse(response.body)
  rescue StandardError => e
    $LOG.error('API_FETCH_JSON', 'ERROR encountered while fetching json from ' + book_api_host)
    puts e.backtrace.join("\n")
    []
  end
end

def book_google_json_get(isbn)
  $LOG.debug('API_FETCH_GOOGLE_JSON', " => #{isbn}")
  begin
    uri = URI.parse("https://www.googleapis.com/books/v1/volumes?q=isbn:#{isbn}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    response = http.get(uri.request_uri)
    JSON.parse(response.body)
  rescue StandardError => e
    $LOG.error('API_FETCH_JSON', 'ERROR encountered while fetching json from https://www.googleapis.com')
    puts e.backtrace.join("\n")
    []
  end
end

def saveJSON(book_id, data)
  $LOG.info "submitting #{data['filename']}"
  uri = URI.parse('https://localhost')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  request = Net::HTTP::Post.new("/api/v2/book/#{book_id}/json")
  request.add_field('Content-Type', 'application/json; charset=utf-8')
  request.body = data.to_json
  response = http.request(request)
  $LOG.info response.body

  response.body.include? '{"success":true}'
end

def getBookList
  $LOG.info 'getting booklist from server'
  uri = URI.parse('https://localhost/api/v2/books/update/libgen/json')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  request = Net::HTTP::Get.new(uri.path)
  response = http.request(request)
  JSON.parse(response.body)['results']
end

list = getBookList
_i = 0

list.each do |book|
  _i += 1
  md5 = book['md5']

  libgen = book_json_get(md5)
  google = book_google_json_get(book['isbn13'])

  p libgen
  p google

  data = {}
  data['libgen'] = libgen.first
  if !google.keys.include?('error') && (google['totalItems'] > 0)
    data['google'] = google['items'].first
    data['title'] = google['items'].first['volumeInfo']['title']
    data['authors'] = google['items'].first['volumeInfo']['authors']
    if google['items'].first['volumeInfo'].key?('imageLinks')
      data['cover_url'] = google['items'].first['volumeInfo']['imageLinks']['thumbnail']
    end
  end

  if !data['libgen'].nil? && data['libgen'].keys.include?('coverurl')
    json = data['libgen']
    data['title'] = json['title']
    data['authors'] = json['author'].split(', ')
  end

  saveJSON(book['_id'], data)
  $LOG.info "progress #{_i}/#{list.length}"
  sleep 2
end
